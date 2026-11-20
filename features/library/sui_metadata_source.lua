-- sui_metadata_source.lua — Simple UI
-- Fast, cacheable access to book metadata for library browsing/filtering.
--
-- Two data sources are combined into one resolved row per book:
--   1. CoverBrowser's bookinfo_cache.sqlite3 (via BookInfoManager) — the
--      primary source, populated as the user opens/scans books.
--   2. Calibre's metadata.calibre (when present under base_dir) — the
--      curated source for series (name and index are taken together); for
--      every other field it only fills gaps in the bookinfo row, and it
--      contributes books the bookinfo DB does not know about yet.
--
-- Rows are resolved once per base_dir and cached. A FilterState trail then
-- filters those resolved rows in memory, so a dimension value means the same
-- thing to the facet lists, their counts and the leaf listings (see
-- FilterState.matcher and FilterState.eachFacetValue).
--
-- Every query covers the whole subtree under base_dir. Caches are dropped
-- automatically when the book-info database changes (see sui_bim_stamp);
-- call MetadataSource.clearCache(base_dir) when files change on disk
-- (book added/removed/moved) for that subtree.
--
-- Public API
-- ----------
--   MetadataSource.getMatchingFiles(bim, base_dir, filter_state)
--       -> { {fullpath, filename, title=, authors=, series=, series_key=,
--             series_index=, keywords=}, ... }  sorted by directory, filename
--   MetadataSource.getFacetValues(bim, base_dir, dimension, filter_state, include_empty)
--       -> { {value, count, key=, _first=row}, ... } sorted for display;
--          the "no value" group (key == false) is only listed when
--          include_empty is truthy
--   MetadataSource.getValidRows(bim, base_dir, filter_state, variant, accept)
--       -> rows matching the trail for which accept(row) is true (cached,
--          read-only; `variant` identifies what accept depends on)
--   MetadataSource.getValidFacetCounts(bim, base_dir, dimension, filter_state, variant, accept)
--       -> counts, firsts: per facet key, the number of accepted rows and the
--          paths of the first MetadataSource.FIRST_PATHS of them (cached,
--          read-only)
--   MetadataSource.getFolderSeries(bim, dir)
--       -> { [filename] = {series=, series_index=}, ... } | nil
--   MetadataSource.getSeriesByPath(bim, base_dir)
--       -> { [fullpath] = {series=, series_index=}, ... }  (books with a series, one read for the subtree)
--   MetadataSource.sortFiles(files, active_dimension)  -- mutates in place
--   MetadataSource.clearCache(base_dir)  -- base_dir == nil clears everything

local logger      = require("logger")
local ffiUtil     = require("ffi/util")
local LRU         = require("infra/sui_lru")
local FilterState = require("features/library/sui_filter_state")
local BimStamp    = require("features/library/sui_bim_stamp")
local SUISettings = require("infra/sui_store")

local MetadataSource = {}

local SETTING_PUB_YEAR_OVERRIDES = "simpleui_pub_year_overrides"

-- ---------------------------------------------------------------------------
-- Caches
-- ---------------------------------------------------------------------------

-- Folders whose whole-subtree data is kept at once: the rows of a large
-- library are the biggest item here, and browsing rarely spans more folders.
local MAX_BASE_DIRS = 4
-- Per-trail results kept at once. They only hold references to the shared
-- rows, so a few dozen entries stay small while covering a long drill-down.
local MAX_DERIVED_ENTRIES = 24

-- Keyed by normalized base_dir:
local _scope_rows_cache     = LRU.new{ max_entries = MAX_BASE_DIRS }  -- resolved rows for the whole subtree
local _calibre_index_cache  = LRU.new{ max_entries = MAX_BASE_DIRS }  -- index table | false
-- Scoped by normalized base_dir, keyed by the serialized trail plus a suffix:
local _matching_files_cache = LRU.new{ max_entries = MAX_DERIVED_ENTRIES } -- [trail] = rows matching it
local _facet_values_cache   = LRU.new{ max_entries = MAX_DERIVED_ENTRIES } -- [trail .. "\31" .. dimension] = { {value, count, key=, _first=row}, ... }
local _valid_rows_cache     = LRU.new{ max_entries = MAX_DERIVED_ENTRIES } -- [trail .. "\29" .. variant] = rows accepted by the caller
local _valid_facets_cache   = LRU.new{ max_entries = MAX_DERIVED_ENTRIES } -- [trail .. "\31" .. dimension .. "\29" .. variant] = { counts, reprs }

local _all_caches = {
    _scope_rows_cache, _calibre_index_cache, _matching_files_cache,
    _facet_values_cache, _valid_rows_cache, _valid_facets_cache,
}

local function normalizeBaseDir(dir)
    while #dir > 1 and dir:sub(-1) == "/" do dir = dir:sub(1, -2) end
    return dir
end

local function serializeTrail(filter_state)
    local parts = {}
    for _, entry in ipairs(filter_state and filter_state.trail or {}) do
        parts[#parts + 1] = entry.dimension
        parts[#parts + 1] = (entry.value == false) and "\0" or tostring(entry.value)
    end
    return table.concat(parts, "\31")
end

local function isWithin(base_dir, prefix)
    return base_dir == prefix or base_dir:sub(1, #prefix + 1) == prefix .. "/"
end

-- Clears every cache entry whose base_dir is `base_dir` or a subdirectory
-- of it (so invalidating a parent also invalidates narrower queries below
-- it). base_dir == nil clears everything.
local _doc_year_cache = {}

function MetadataSource.clearCache(base_dir)
    if not base_dir then
        _doc_year_cache = {}
        for _, cache in ipairs(_all_caches) do cache:clear() end
        return
    end
    local prefix = normalizeBaseDir(base_dir)
    local function belowPrefix(key, scope) return isWithin(scope or key, prefix) end
    for _, cache in ipairs(_all_caches) do cache:removeWhere(belowPrefix) end
end

-- Stamp of the book-info database the caches were filled from.
local _cache_stamp = nil

-- Drops every cache when the book-info database changed since the last query.
local function syncWithDatabase()
    local stamp = BimStamp.get() or ""
    if stamp ~= _cache_stamp then
        if _cache_stamp ~= nil then MetadataSource.clearCache() end
        _cache_stamp = stamp
    end
end

-- ---------------------------------------------------------------------------
-- Calibre metadata.calibre backfill & document metadata fallback
-- ---------------------------------------------------------------------------

local function findCalibreDir(start_path)
    if not start_path or start_path == "" then return nil end
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not (ok_lfs and lfs) then return nil end

    local function hasMeta(dir)
        return (lfs.attributes(dir .. "/metadata.calibre", "mode") == "file") or
               (lfs.attributes(dir .. "/.metadata.calibre", "mode") == "file")
    end

    local dir = start_path
    if lfs.attributes(dir, "mode") == "file" then
        dir = dir:match("^(.-)/[^/]+$")
    end

    while dir and dir ~= "" and dir ~= "/" do
        if hasMeta(dir) then return dir end
        dir = dir:match("^(.-)/[^/]+$")
    end

    if G_reader_settings then
        local home = G_reader_settings:readSetting("home_dir")
        if home and hasMeta(home) then return home end
    end

    for _, root in ipairs({ "/mnt/us", "/mnt/onboard", "/mnt/sd" }) do
        if hasMeta(root) then return root end
    end

    return nil
end

local function extractYearFromOpf(opf_text)
    if not opf_text then return nil end
    local pub_date = opf_text:match("<dc:date[^>]-event=[\"']publication[\"'][^>]*>([^<]+)</dc:date>")
    if not pub_date then
        pub_date = opf_text:match("<meta[^>]-property=[\"']dcterms:issued[\"'][^>]*>([^<]+)</meta>")
    end
    if not pub_date then
        pub_date = opf_text:match("<dc:date[^>]*>([^<]+)</dc:date>")
    end
    if pub_date then
        local y = pub_date:match("(%d%d%d%d)")
        if y then
            local num = tonumber(y)
            if num and num > 0 and num < 3000 then return num end
        end
    end
    return nil
end

local function readDocYear(filepath)
    if not filepath or type(filepath) ~= "string" then return nil end
    if _doc_year_cache[filepath] ~= nil then
        return _doc_year_cache[filepath] or nil
    end

    local year = nil
    if filepath:lower():match("%.epub$") then
        local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
        local target = filepath

        -- If file does not exist at filepath, check cross-mount (/mnt/us <-> /mnt/base-us)
        if ok_lfs and lfs then
            if lfs.attributes(target, "mode") ~= "file" then
                if target:sub(1, 8) == "/mnt/us/" then
                    local alt = "/mnt/base-us/" .. target:sub(9)
                    if lfs.attributes(alt, "mode") == "file" then
                        target = alt
                    end
                elseif target:sub(1, 13) == "/mnt/base-us/" then
                    local alt = "/mnt/us/" .. target:sub(14)
                    if lfs.attributes(alt, "mode") == "file" then
                        target = alt
                    end
                end
            end
            -- If still not a file on disk, do not invoke libarchive (prevents terminal error spam)
            if lfs.attributes(target, "mode") ~= "file" then
                _doc_year_cache[filepath] = false
                return nil
            end
        end

        local ok_arc, Archiver = pcall(require, "ffi/archiver")
        if ok_arc and Archiver and Archiver.Reader then
            local reader = Archiver.Reader:new()
            local ok_open = pcall(function() return reader:open(target) end)
            if ok_open and reader then
                pcall(function()
                    for entry in reader:iterate() do
                        if entry.mode == "file" and entry.path:lower():match("%.opf$") then
                            local content = reader:extractToMemory(entry.path)
                            if content then
                                year = extractYearFromOpf(content)
                                if year then break end
                            end
                        end
                    end
                end)
                pcall(function() reader:close() end)
            end
        end
    end

    _doc_year_cache[filepath] = year or false
    return year
end

-- Loads metadata.calibre reachable from `dir` directly from JSON and returns a lookup table
-- keyed by full path and filename: { [fullpath] = {title, authors, series, series_index,
-- keywords, pubdate, pub_year}, ... }. Returns false when none exists.
-- Cached for the session (per base_dir actually queried).
local function loadCalibreIndex(dir)
    local base = findCalibreDir(dir) or dir
    local cached = _calibre_index_cache:get(base)
    if cached ~= nil then return cached end

    local file_path = nil
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok_lfs and lfs then
        if lfs.attributes(base .. "/metadata.calibre", "mode") == "file" then
            file_path = base .. "/metadata.calibre"
        elseif lfs.attributes(base .. "/.metadata.calibre", "mode") == "file" then
            file_path = base .. "/.metadata.calibre"
        end
    end

    if not file_path then
        _calibre_index_cache:put(base, false)
        return false
    end

    local raw = nil
    local ok_rj, rapidjson = pcall(require, "rapidjson")
    if ok_rj and rapidjson and type(rapidjson.load) == "function" then
        pcall(function() raw = rapidjson.load(file_path) end)
    end
    if not raw then
        local ok_json, json = pcall(require, "json")
        if ok_json and json and type(json.decode) == "function" then
            pcall(function()
                local f = io.open(file_path, "r")
                if f then
                    local content = f:read("*all")
                    f:close()
                    if content then raw = json.decode(content) end
                end
            end)
        end
    end

    if not raw then
        _calibre_index_cache:put(base, false)
        return false
    end

    local books = raw.books or (type(raw) == "table" and raw)
    if type(books) ~= "table" then
        _calibre_index_cache:put(base, false)
        return false
    end

    local index = {}
    for _, b in ipairs(books) do
        local lpath = b.lpath
        if lpath and type(lpath) == "string" then
            local norm_lpath = lpath:gsub("\\", "/")
            while #norm_lpath > 0 and norm_lpath:sub(1, 1) == "/" do
                norm_lpath = norm_lpath:sub(2)
            end
            local fullpath = base .. "/" .. norm_lpath

            local authors_str = nil
            if type(b.authors) == "table" and #b.authors > 0 then
                authors_str = table.concat(b.authors, "\n")
            elseif type(b.authors) == "string" and b.authors ~= "" then
                authors_str = b.authors
            end

            local keywords_str = nil
            if type(b.tags) == "table" and #b.tags > 0 then
                local valid = {}
                for _, tag in ipairs(b.tags) do
                    if type(tag) == "string" and tag ~= "" and not tag:match("^PLUGBOARD TEMPLATE ERROR") then
                        valid[#valid + 1] = tag
                    end
                end
                if #valid > 0 then
                    keywords_str = table.concat(valid, "\n")
                end
            elseif type(b.tags) == "string" and b.tags ~= "" then
                if not b.tags:match("^PLUGBOARD TEMPLATE ERROR") then
                    keywords_str = b.tags
                end
            end

            local series = (type(b.series) == "string" and b.series ~= "") and b.series or nil
            local series_index = (type(b.series_index) == "number") and b.series_index or nil
            local title = (type(b.title) == "string" and b.title ~= "") and b.title or nil

            local pubdate_str = (type(b.pubdate) == "string" and b.pubdate)
                             or (type(b.date) == "string" and b.date)
                             or (type(b.timestamp) == "string" and b.timestamp)
            local pub_year = nil
            if pubdate_str then
                local y = pubdate_str:match("(%d%d%d%d)")
                if y then
                    local num = tonumber(y)
                    if num and num > 0 and num < 3000 then pub_year = num end
                end
            end

            local item = {
                title = title,
                authors = authors_str,
                series = series,
                series_index = series_index,
                keywords = keywords_str,
                pubdate = pubdate_str,
                pub_year = pub_year,
            }
            index[fullpath] = item
            local fname = fullpath:match("([^/]+)$")
            if fname and not index[fname] then
                index[fname] = item
            end
        end
    end

    index = next(index) and index or false
    _calibre_index_cache:put(base, index)
    return index
end

-- ---------------------------------------------------------------------------
-- Row resolution
-- ---------------------------------------------------------------------------

local function nonEmpty(value)
    if value ~= nil and value ~= "" then return value end
end

local function cleanKeywords(raw)
    if not raw or raw == "" then return nil end
    local valid = {}
    for token in raw:gmatch("[^\n]+") do
        if not token:match("^PLUGBOARD TEMPLATE ERROR") then
            valid[#valid + 1] = token
        end
    end
    if #valid > 0 then
        return table.concat(valid, "\n")
    end
    return nil
end

-- Resolves a bookinfo row in place, optionally against its Calibre record.
-- The Calibre series wins as a name/index pair; the bookinfo index only
-- survives when both sources name the same series. Series names are
-- normalized (see FilterState.parseSeries) and get a comparison key.
local function resolveRow(row, cal)
    local name, suffix_index = FilterState.parseSeries(row.series)
    local index = row.series_index or suffix_index

    if cal then
        local cal_name, cal_suffix = FilterState.parseSeries(cal.series)
        if cal_name then
            local same = name ~= nil and FilterState.seriesKey(name) == FilterState.seriesKey(cal_name)
            name, index = cal_name, cal.series_index or cal_suffix or (same and index) or nil
        end
        row.title    = nonEmpty(row.title)    or cal.title
        row.authors  = nonEmpty(row.authors)  or cal.authors
        row.keywords = nonEmpty(row.keywords) or cal.keywords
        row.pubdate  = cal.pubdate
        row.pub_year = cal.pub_year
    end

    local overrides = SUISettings:readSetting(SETTING_PUB_YEAR_OVERRIDES)
    if overrides and overrides[row[1]] ~= nil then
        row.pub_year = overrides[row[1]]
    end

    if not row.pub_year then
        row.pub_year = readDocYear(row[1])
    end

    row.authors, row.keywords = nonEmpty(row.authors), cleanKeywords(row.keywords)
    row.series, row.series_index = name, index
    row.series_key = name and FilterState.seriesKey(name)
end

-- ---------------------------------------------------------------------------
-- Scope query
-- ---------------------------------------------------------------------------

local _SQL_SCOPE = "SELECT directory, filename, title, authors, series, series_index, keywords"
                .. " FROM bookinfo WHERE directory GLOB ?"
                .. " ORDER BY directory ASC, filename ASC"

-- Runs `sql` with one bound parameter and passes every result row to
-- `on_row`. Returns false when the query fails.
local function eachRow(bim, sql, param, on_row)
    local stmt
    local ok, err = pcall(function()
        bim:openDbConnection()
        stmt = bim.db_conn:prepare(sql)
        stmt:bind(param)
        while true do
            local row = stmt:step()
            if not row then break end
            on_row(row)
        end
    end)
    if stmt then pcall(function() stmt:finalize() end) end
    if not ok then logger.warn("sui_metadata_source: SQL error:", tostring(err)) end
    return ok
end

local function queryBookInfo(bim, base_dir)
    local rows = {}
    local ok = eachRow(bim, _SQL_SCOPE, base_dir .. "/*", function(row)
        -- The `directory` column always stores a trailing slash, so the
        -- full path is a plain concatenation.
        rows[#rows + 1] = {
            row[1] .. row[2], row[2],
            title = row[3], authors = row[4], series = row[5],
            series_index = tonumber(row[6]), keywords = row[7],
        }
    end)
    return ok and rows or nil
end

local _SQL_FOLDER_SERIES = "SELECT filename, series, series_index FROM bookinfo WHERE directory = ?"

-- Series name and index of every book the database holds for the folder
-- `dir` (trailing slash included, subfolders excluded), in a single query.
-- Returns nil when the query fails.
function MetadataSource.getFolderSeries(bim, dir)
    local props = {}
    local ok = eachRow(bim, _SQL_FOLDER_SERIES, dir, function(row)
        props[row[1]] = { series = row[2], series_index = tonumber(row[3]) }
    end)
    return ok and props or nil
end

-- Resolved rows for every book under base_dir: bookinfo rows in
-- (directory, filename) order, then Calibre-only books in path order.
local function fetchScopeRows(bim, base_dir)
    local rows = queryBookInfo(bim, base_dir)
    if not rows then return {} end

    local cal_index = loadCalibreIndex(base_dir)
    local seen = {}
    for _, row in ipairs(rows) do
        seen[row[1]] = true
        local cal = cal_index and (cal_index[row[1]] or (row[2] and cal_index[row[2]]))
        resolveRow(row, cal)
    end

    if cal_index then
        local extra = {}
        for fullpath in pairs(cal_index) do
            if fullpath:find("/", 1, true) and not seen[fullpath] then
                extra[#extra + 1] = fullpath
            end
        end
        table.sort(extra)
        for _, fullpath in ipairs(extra) do
            local fname = fullpath:match("([^/]+)$")
            if fname then
                local cal = cal_index[fullpath]
                local row = {
                    fullpath, fname,
                    title = cal.title, authors = cal.authors, series = cal.series,
                    series_index = cal.series_index, keywords = cal.keywords,
                    pubdate = cal.pubdate, pub_year = cal.pub_year,
                }
                resolveRow(row)
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end

local function getScopeRows(bim, base_dir)
    base_dir = normalizeBaseDir(base_dir)
    local rows = _scope_rows_cache:get(base_dir)
    if not rows then
        rows = _scope_rows_cache:put(base_dir, fetchScopeRows(bim, base_dir))
    end
    return rows
end

-- Series name and index of every book under base_dir that has a series, by
-- full path, from the cached rows of the whole subtree (Calibre included).
-- The map is kept with the rows it was built from and goes with them.
local _series_by_rows = setmetatable({}, { __mode = "k" })

function MetadataSource.getSeriesByPath(bim, base_dir)
    if not bim or not base_dir then return {} end
    syncWithDatabase()
    local rows = getScopeRows(bim, base_dir)
    local map = _series_by_rows[rows]
    if not map then
        map = {}
        for _, row in ipairs(rows) do
            if row.series then map[row[1]] = { series = row.series, series_index = row.series_index } end
        end
        _series_by_rows[rows] = map
    end
    return map
end

local function copyArray(array)
    local copy = {}
    for i, value in ipairs(array) do copy[i] = value end
    return copy
end

-- The cached rows matching the trail. Internal: the array is shared, so
-- callers must not mutate it.
local function matchingRows(bim, base_dir, filter_state)
    base_dir = normalizeBaseDir(base_dir)
    local trail_key = serializeTrail(filter_state)
    local cached = _matching_files_cache:get(trail_key, base_dir)
    if cached then return cached end

    local rows = getScopeRows(bim, base_dir)
    local trail = filter_state and filter_state.trail
    if trail and #trail > 0 then
        local matches = FilterState.matcher(trail)
        local filtered = {}
        for _, row in ipairs(rows) do
            if matches(row) then filtered[#filtered + 1] = row end
        end
        rows = filtered
    end
    return _matching_files_cache:put(trail_key, rows, 0, base_dir)
end

-- Returns a COPY of the (internally cached) matching-files array. Callers
-- are free to sort or otherwise mutate the array they receive — the cache
-- itself is never touched here, so a caller sorting by one active_dimension
-- can never corrupt the result another caller expects in a different order.
function MetadataSource.getMatchingFiles(bim, base_dir, filter_state)
    if not bim or not base_dir then return {} end
    syncWithDatabase()
    return copyArray(matchingRows(bim, base_dir, filter_state))
end

-- ---------------------------------------------------------------------------
-- Collation
-- ---------------------------------------------------------------------------

local function strcollSafe(a, b)
    if a == b then return false end
    if not a then return false end
    if not b then return true end
    return ffiUtil.strcoll(a, b)
end

-- ---------------------------------------------------------------------------
-- Facet values (grouping + counts)
-- ---------------------------------------------------------------------------

-- The grouping pass + strcoll sort below is the expensive part of this
-- function (O(#matching files) to group, O(n log n) strcoll comparisons to
-- sort) — cheap for a single call, but this function is called on every
-- author/series/tags tab switch, so without memoization it re-pays that
-- cost every time even when the matching rows are a cache hit. Cached under
-- the same coordinates as _matching_files_cache, with the dimension appended,
-- and invalidated by the same MetadataSource.clearCache(base_dir).
--
-- Values are grouped by their comparison key; the entry displays the
-- spelling of the first row that contributed to it.
local function computeFacetValues(rows, definition)
    local groups, out = {}, {}
    local current
    local function add(key, value)
        local entry = groups[key]
        if not entry then
            entry = { value, 0, key = key, _first = current }
            groups[key] = entry
            out[#out + 1] = entry
        end
        entry[2] = entry[2] + 1
    end

    for _, row in ipairs(rows) do
        current = row
        FilterState.eachFacetValue(row, definition, add)
    end

    table.sort(out, function(a, b) return strcollSafe(a[1], b[1]) end)
    return out
end

function MetadataSource.getFacetValues(bim, base_dir, dimension, filter_state, include_empty)
    if not FilterState.isDimension(dimension) then return {} end
    syncWithDatabase()

    local scope = normalizeBaseDir(base_dir)
    local key = serializeTrail(filter_state) .. "\31" .. dimension
    local cached = _facet_values_cache:get(key, scope)
    if not cached then
        cached = _facet_values_cache:put(key, computeFacetValues(
            matchingRows(bim, base_dir, filter_state), FilterState.DIMENSIONS[dimension]), 0, scope)
    end
    -- Return a shallow copy: cheap (copies entry refs, not rows), and keeps
    -- callers free to sort/mutate what they receive without corrupting the
    -- cache — same contract as getMatchingFiles. The cache always holds the
    -- full list; the "no value" group is dropped from the copy only.
    if include_empty then return copyArray(cached) end
    local values = {}
    for i = 1, #cached do
        if cached[i].key ~= false then values[#values + 1] = cached[i] end
    end
    return values
end

-- ---------------------------------------------------------------------------
-- Validated rows (rows the caller's predicate accepts)
-- ---------------------------------------------------------------------------

-- `accept(row)` is typically a filesystem check (file exists, file chooser
-- shows it), which costs a syscall per row. The outcome is cached under
-- `variant`, a string naming the state accept depends on: callers must use
-- the same variant only for predicates that behave identically. Returned
-- arrays are shared — callers must not mutate them.
function MetadataSource.getValidRows(bim, base_dir, filter_state, variant, accept)
    if not bim or not base_dir then return {} end
    syncWithDatabase()

    local scope = normalizeBaseDir(base_dir)
    local key = serializeTrail(filter_state) .. "\29" .. variant
    local valid = _valid_rows_cache:get(key, scope)
    if not valid then
        valid = {}
        for _, row in ipairs(matchingRows(bim, base_dir, filter_state)) do
            if accept(row) then valid[#valid + 1] = row end
        end
        _valid_rows_cache:put(key, valid, 0, scope)
    end
    return valid
end

-- Books kept per facet: enough to fill a folder cover and look past books
-- without cover art.
MetadataSource.FIRST_PATHS = 8

-- Per facet key (entry.key of getFacetValues): the number of accepted rows
-- and the paths of the first FIRST_PATHS of them. Same caching contract as
-- getValidRows.
function MetadataSource.getValidFacetCounts(bim, base_dir, dimension, filter_state, variant, accept)
    if not FilterState.isDimension(dimension) then return {}, {} end

    local rows = MetadataSource.getValidRows(bim, base_dir, filter_state, variant, accept)
    local scope = normalizeBaseDir(base_dir)
    local key = serializeTrail(filter_state) .. "\31" .. dimension .. "\29" .. variant
    local cached = _valid_facets_cache:get(key, scope)
    if not cached then
        local counts, firsts, first_years = {}, {}, {}
        local current_row
        local function count(facet_key)
            counts[facet_key] = (counts[facet_key] or 0) + 1
            local first = firsts[facet_key]
            if not first then
                firsts[facet_key] = { current_row[1] }
            elseif #first < MetadataSource.FIRST_PATHS then
                first[#first + 1] = current_row[1]
            end
            if current_row.pub_year then
                local fy = first_years[facet_key]
                if not fy or current_row.pub_year < fy then
                    first_years[facet_key] = current_row.pub_year
                end
            end
        end
        local definition = FilterState.DIMENSIONS[dimension]
        for _, row in ipairs(rows) do
            current_row = row
            FilterState.eachFacetValue(row, definition, count)
        end
        cached = _valid_facets_cache:put(key, { counts, firsts, first_years }, 0, scope)
    end
    return cached[1], cached[2], cached[3]
end

-- ---------------------------------------------------------------------------
-- Sorting
-- ---------------------------------------------------------------------------

-- Sort by: series (author dimension only), series_index, title, filename.
function MetadataSource.sortFiles(files, active_dimension)
    local is_author = (active_dimension == "author")
    table.sort(files, function(a, b)
        if is_author then
            local as, bs = a.series_key, b.series_key
            if as ~= bs then return strcollSafe(as, bs) end
        end
        local ai, bi = a.series_index, b.series_index
        if ai ~= bi then
            if not ai then return false end
            if not bi then return true end
            return ai < bi
        end
        local at = a.title or a[2]
        local bt = b.title or b[2]
        if at ~= bt then return strcollSafe(at, bt) end
        return strcollSafe(a[2], b[2])
    end)
end

-- ---------------------------------------------------------------------------
-- Publication year overrides
-- ---------------------------------------------------------------------------

local findCalibreBase = findCalibreDir

function MetadataSource.getBookPubYear(filepath, base_dir)
    if not filepath then return nil end
    local overrides = SUISettings:readSetting(SETTING_PUB_YEAR_OVERRIDES)
    if overrides and overrides[filepath] ~= nil then
        return overrides[filepath]
    end

    local ok_ds, ds = pcall(function()
        local DocSettings = require("docsettings")
        return DocSettings:open(filepath)
    end)
    if ok_ds and ds then
        local y = ds:readSetting("custom_pub_year")
        if y ~= nil then return tonumber(y) end
        local props = ds:readSetting("doc_props")
        if type(props) == "table" and type(props.date) == "string" then
            local dy = props.date:match("(%d%d%d%d)")
            if dy then
                local num = tonumber(dy)
                if num and num > 0 and num < 3000 then return num end
            end
        end
    end

    local fname = filepath:match("([^/]+)$")
    local bdir = base_dir or findCalibreDir(filepath) or filepath:match("^(.-)/[^/]+$")
    if bdir then
        local cal_index = loadCalibreIndex(bdir)
        local cal = cal_index and (cal_index[filepath] or (fname and cal_index[fname]))
        if cal and cal.pub_year then
            return cal.pub_year
        end
    end

    local doc_y = readDocYear(filepath)
    if doc_y then return doc_y end

    local ok_dr, DocumentRegistry = pcall(require, "document/documentregistry")
    if ok_dr and DocumentRegistry and DocumentRegistry.openDocument then
        local ok, doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, filepath)
        if ok and doc then
            local props = doc.getProps and doc:getProps()
            if not props and doc.getDocumentProps then
                props = doc:getDocumentProps()
            end
            if doc.close then pcall(doc.close, doc) end
            if props then
                local date_str = props.pubdate or props.date or props.issued
                if type(date_str) == "string" then
                    local matched = date_str:match("(%d%d%d%d)")
                    if matched then
                        local num = tonumber(matched)
                        if num and num > 0 and num < 3000 then return num end
                    end
                end
            end
        end
    end

    return nil
end

function MetadataSource.setBookPubYear(filepath, year)
    if not filepath then return end
    local overrides = SUISettings:readSetting(SETTING_PUB_YEAR_OVERRIDES)
    local copy = {}
    if overrides then
        for k, v in pairs(overrides) do copy[k] = v end
    end
    copy[filepath] = year
    SUISettings:saveSetting(SETTING_PUB_YEAR_OVERRIDES, copy)
    SUISettings:flush()

    pcall(function()
        local DocSettings = require("docsettings")
        local ds = DocSettings:open(filepath)
        if ds then
            if year then
                ds:saveSetting("custom_pub_year", year)
            else
                ds:delSetting("custom_pub_year")
            end
            ds:flush()
        end
    end)

    MetadataSource.clearCache()
    local ok_uim, UIManager = pcall(require, "ui/uimanager")
    local ok_evt, Event = pcall(require, "ui/event")
    if ok_uim and ok_evt and UIManager and Event then
        UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
    end
end

return MetadataSource
