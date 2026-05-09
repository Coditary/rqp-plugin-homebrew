plugin = {}

local PLUGIN_ID = "homebrew"
local PLUGIN_NAME = "Homebrew"
local PLUGIN_VERSION = "0.2.0"
local HOMEBREW_INSTALL_URL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
local BREW_DETECT_COMMAND = "command -v brew 2>/dev/null || { [ -x /opt/homebrew/bin/brew ] && printf '%s\\n' /opt/homebrew/bin/brew; } || { [ -x /usr/local/bin/brew ] && printf '%s\\n' /usr/local/bin/brew; } || { [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && printf '%s\\n' /home/linuxbrew/.linuxbrew/bin/brew; }"
local BREW_RECHECK_COMMAND = "{ [ -x /opt/homebrew/bin/brew ] && printf '%s\\n' /opt/homebrew/bin/brew; } || { [ -x /usr/local/bin/brew ] && printf '%s\\n' /usr/local/bin/brew; } || { [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && printf '%s\\n' /home/linuxbrew/.linuxbrew/bin/brew; } || command -v brew 2>/dev/null"
local BREW_INSTALL_COMMAND = "NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL " .. HOMEBREW_INSTALL_URL .. ")\""
local JSON_NULL = {}
local unpack_values = table.unpack or unpack

local cached_json_decoder = nil

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function json_value(value)
    if value == JSON_NULL then
        return nil
    end

    return value
end

local function is_safe_token(value)
    return tostring(value or ""):match("^[A-Za-z0-9_./:@%%+=,-]+$") ~= nil
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function shell_arg(value)
    local text = tostring(value)
    if is_safe_token(text) then
        return text
    end

    return shell_quote(text)
end

local function shallow_copy(value)
    local copy = {}
    for key, item in pairs(value or {}) do
        copy[key] = item
    end
    return copy
end

local function read_field(value, key)
    if value == nil then
        return nil
    end

    local ok, result = pcall(function()
        return value[key]
    end)
    if ok then
        return result
    end

    return nil
end

local function read_nested_field(value, ...)
    local current = value
    local keys = { ... }
    for _, key in ipairs(keys) do
        current = read_field(current, key)
        if current == nil then
            return nil
        end
    end

    return current
end

local function merge_extra_fields(existing, additions)
    local merged = shallow_copy(type(existing) == "table" and existing or {})
    for key, value in pairs(additions or {}) do
        merged[key] = value
    end
    return merged
end

local function append_all(target, items)
    for _, item in ipairs(items or {}) do
        target[#target + 1] = item
    end
end

local function first_nonempty(...)
    local values = { ... }
    for _, value in ipairs(values) do
        if value ~= JSON_NULL then
            local value_type = type(value)
            if value_type == "string" then
                local trimmed = trim(value)
                if trimmed ~= "" then
                    return trimmed
                end
            elseif value ~= nil then
                return value
            end
        end
    end

    return nil
end

local function call_logger(context, level, message)
    if context == nil or context.log == nil then
        return
    end

    local fn = context.log[level]
    if type(fn) == "function" then
        fn(message)
    end
end

local function emit_event(context, name, payload)
    if context == nil or context.events == nil then
        return
    end

    local fn = context.events[name]
    if type(fn) == "function" then
        fn(payload)
    end
end

local function begin_step(context, label)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.begin_step
    if type(fn) == "function" then
        fn(label)
    end
end

local function tx_success(context)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.success
    if type(fn) == "function" then
        fn()
    end
end

local function tx_failed(context, message)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.failed
    if type(fn) == "function" then
        fn(message)
    end
end

local function run_global(command)
    if reqpack == nil or reqpack.exec == nil or type(reqpack.exec.run) ~= "function" then
        return {
            success = false,
            stdout = "",
            stderr = "reqpack.exec.run unavailable",
        }
    end

    return reqpack.exec.run(command)
end

local function make_exec_runner(context)
    if context ~= nil and context.exec ~= nil and type(context.exec.run) == "function" then
        return function(command)
            return context.exec.run(command)
        end
    end

    return run_global
end

local function normalize_json_tree(value, null_sentinel, seen)
    if null_sentinel ~= nil and value == null_sentinel then
        return JSON_NULL
    end

    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end

    local normalized = {}
    seen[value] = normalized

    for key, item in pairs(value) do
        normalized[key] = normalize_json_tree(item, null_sentinel, seen)
    end

    return normalized
end

local function codepoint_to_utf8(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    end

    if codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    if codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + (math.floor(codepoint / 0x1000) % 0x40),
        0x80 + (math.floor(codepoint / 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

local function decode_json_internal(raw)
    local text = tostring(raw or "")
    local length = #text
    local index = 1

    local function decode_error(message)
        error(message .. " at byte " .. tostring(index), 0)
    end

    local function peek()
        return text:sub(index, index)
    end

    local function skip_whitespace()
        while index <= length do
            local byte = text:byte(index)
            if byte == 32 or byte == 9 or byte == 10 or byte == 13 then
                index = index + 1
            else
                break
            end
        end
    end

    local parse_value

    local function parse_string()
        index = index + 1
        local parts = {}
        local segment_start = index

        while index <= length do
            local current = text:sub(index, index)

            if current == '"' then
                parts[#parts + 1] = text:sub(segment_start, index - 1)
                index = index + 1
                return table.concat(parts)
            end

            if current == "\\" then
                parts[#parts + 1] = text:sub(segment_start, index - 1)
                index = index + 1

                if index > length then
                    decode_error("unterminated escape sequence")
                end

                local escape = text:sub(index, index)
                if escape == '"' or escape == "\\" or escape == "/" then
                    parts[#parts + 1] = escape
                    index = index + 1
                elseif escape == "b" then
                    parts[#parts + 1] = "\b"
                    index = index + 1
                elseif escape == "f" then
                    parts[#parts + 1] = "\f"
                    index = index + 1
                elseif escape == "n" then
                    parts[#parts + 1] = "\n"
                    index = index + 1
                elseif escape == "r" then
                    parts[#parts + 1] = "\r"
                    index = index + 1
                elseif escape == "t" then
                    parts[#parts + 1] = "\t"
                    index = index + 1
                elseif escape == "u" then
                    local hex = text:sub(index + 1, index + 4)
                    if #hex ~= 4 or hex:match("^[0-9a-fA-F]+$") == nil then
                        decode_error("invalid unicode escape")
                    end

                    parts[#parts + 1] = codepoint_to_utf8(tonumber(hex, 16))
                    index = index + 5
                else
                    decode_error("unsupported escape sequence")
                end

                segment_start = index
            else
                local byte = text:byte(index)
                if byte ~= nil and byte < 32 then
                    decode_error("control character in string")
                end

                index = index + 1
            end
        end

        decode_error("unterminated string")
    end

    local function parse_number()
        local start_index = index
        local current = peek()

        if current == "-" then
            index = index + 1
        end

        current = peek()
        if current == "0" then
            index = index + 1
        elseif current:match("%d") ~= nil then
            while peek():match("%d") ~= nil do
                index = index + 1
            end
        else
            decode_error("invalid number")
        end

        current = peek()
        if current == "." then
            index = index + 1
            if peek():match("%d") == nil then
                decode_error("invalid decimal number")
            end

            while peek():match("%d") ~= nil do
                index = index + 1
            end
        end

        current = peek()
        if current == "e" or current == "E" then
            index = index + 1
            current = peek()
            if current == "+" or current == "-" then
                index = index + 1
            end

            if peek():match("%d") == nil then
                decode_error("invalid exponent")
            end

            while peek():match("%d") ~= nil do
                index = index + 1
            end
        end

        local number = tonumber(text:sub(start_index, index - 1))
        if number == nil then
            decode_error("invalid numeric value")
        end

        return number
    end

    local function parse_array()
        local items = {}
        index = index + 1
        skip_whitespace()

        if peek() == "]" then
            index = index + 1
            return items
        end

        while true do
            items[#items + 1] = parse_value()
            skip_whitespace()

            local current = peek()
            if current == "," then
                index = index + 1
                skip_whitespace()
            elseif current == "]" then
                index = index + 1
                return items
            else
                decode_error("expected ',' or ']' in array")
            end
        end
    end

    local function parse_object()
        local object = {}
        index = index + 1
        skip_whitespace()

        if peek() == "}" then
            index = index + 1
            return object
        end

        while true do
            if peek() ~= '"' then
                decode_error("expected string key")
            end

            local key = parse_string()
            skip_whitespace()

            if peek() ~= ":" then
                decode_error("expected ':' after key")
            end

            index = index + 1
            skip_whitespace()
            object[key] = parse_value()
            skip_whitespace()

            local current = peek()
            if current == "," then
                index = index + 1
                skip_whitespace()
            elseif current == "}" then
                index = index + 1
                return object
            else
                decode_error("expected ',' or '}' in object")
            end
        end
    end

    function parse_value()
        skip_whitespace()
        local current = peek()

        if current == '"' then
            return parse_string()
        end

        if current == "{" then
            return parse_object()
        end

        if current == "[" then
            return parse_array()
        end

        if current == "-" or current:match("%d") ~= nil then
            return parse_number()
        end

        if text:sub(index, index + 3) == "true" then
            index = index + 4
            return true
        end

        if text:sub(index, index + 4) == "false" then
            index = index + 5
            return false
        end

        if text:sub(index, index + 3) == "null" then
            index = index + 4
            return JSON_NULL
        end

        decode_error("unexpected token")
    end

    local value = parse_value()
    skip_whitespace()
    if index <= length then
        decode_error("trailing content")
    end

    return value
end

local function load_json_decoder()
    if cached_json_decoder ~= nil then
        return cached_json_decoder
    end

    local candidates = {
        function()
            local ok, module = pcall(require, "cjson.safe")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    local value, err = module.decode(raw)
                    if err ~= nil then
                        error(err, 0)
                    end

                    return normalize_json_tree(value, module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "cjson")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    return normalize_json_tree(module.decode(raw), module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "dkjson")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    local value, _, err = module.decode(raw, 1, nil)
                    if err ~= nil then
                        error(err, 0)
                    end

                    return normalize_json_tree(value, module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "lunajson")
            if ok and module ~= nil and type(module.decode) == "function" then
                return function(raw)
                    return normalize_json_tree(module.decode(raw), module.null)
                end
            end
        end,
        function()
            local ok, module = pcall(require, "json")
            if ok and module ~= nil then
                local decode = module.decode or module.Decode
                if type(decode) == "function" then
                    return function(raw)
                        return normalize_json_tree(decode(raw), module.null)
                    end
                end
            end
        end,
    }

    for _, candidate in ipairs(candidates) do
        local ok, decoder = pcall(candidate)
        if ok and type(decoder) == "function" then
            cached_json_decoder = decoder
            return cached_json_decoder
        end
    end

    cached_json_decoder = decode_json_internal
    return cached_json_decoder
end

local function decode_json(raw)
    local decoder = load_json_decoder()
    local ok, value, err = pcall(decoder, raw)
    if not ok then
        return nil, trim(value)
    end

    if value == nil then
        return nil, first_nonempty(err, "json decode returned nil")
    end

    return value, nil
end

local function build_command(binary, args)
    local parts = { shell_arg(binary) }
    for _, arg in ipairs(args or {}) do
        parts[#parts + 1] = shell_arg(arg)
    end

    return table.concat(parts, " ")
end

local function detect_brew_binary(exec_runner, detect_command)
    local result = exec_runner(detect_command or BREW_DETECT_COMMAND)
    if result ~= nil and result.success then
        local binary = trim(result.stdout)
        if binary ~= "" then
            return binary
        end
    end

    return nil
end

local function is_not_found_error(stderr)
    local text = lower(stderr)
    return text:find("no available formula", 1, true) ~= nil
        or text:find("no available cask", 1, true) ~= nil
        or text:find("no formulae or casks found", 1, true) ~= nil
        or text:find("no formula or cask found", 1, true) ~= nil
end

local function run_brew(context, args, options)
    options = options or {}
    local exec_runner = options.exec_runner or make_exec_runner(context)
    local brew_binary = options.brew_binary or detect_brew_binary(exec_runner)

    if brew_binary == nil then
        return nil, "homebrew not installed", nil
    end

    local command = build_command(brew_binary, args)
    return exec_runner(command), nil, command
end

local function run_brew_json(context, args, options)
    options = options or {}
    local result, run_error = run_brew(context, args, options)
    if result == nil then
        return nil, run_error, nil
    end

    local stdout = trim(result.stdout)
    local stderr = trim(result.stderr)

    if stdout == "" then
        if options.allow_missing and (result.success or is_not_found_error(stderr)) then
            return {
                formulae = {},
                casks = {},
            }, nil, result
        end

        return nil, first_nonempty(stderr, "homebrew returned empty JSON"), result
    end

    local decoded, decode_error = decode_json(stdout)
    if decoded == nil then
        return nil, first_nonempty(decode_error, "failed to decode homebrew JSON"), result
    end

    return decoded, nil, result
end

local function ensure_brew_installed(context)
    local exec_runner = make_exec_runner(context)
    local brew_binary = detect_brew_binary(exec_runner)
    if brew_binary ~= nil then
        return brew_binary, nil
    end

    begin_step(context, "install homebrew")
    call_logger(context, "info", "homebrew missing, running official installer")

    local result = exec_runner(BREW_INSTALL_COMMAND)
    if result == nil or not result.success then
        return nil, first_nonempty(result and result.stderr, result and result.stdout, "homebrew bootstrap failed")
    end

    brew_binary = detect_brew_binary(exec_runner, BREW_RECHECK_COMMAND)
    if brew_binary == nil then
        return nil, "homebrew bootstrap finished but brew binary is still unavailable"
    end

    return brew_binary, nil
end

local function as_string_array(value)
    local items = {}
    if type(value) ~= "table" then
        return items
    end

    for _, item in ipairs(value) do
        if item ~= JSON_NULL then
            local text = trim(item)
            if text ~= "" then
                items[#items + 1] = text
            end
        end
    end

    return items
end

local function unique_strings(values)
    local items = {}
    local seen = {}
    for _, value in ipairs(values or {}) do
        local text = trim(value)
        if text ~= "" and not seen[text] then
            seen[text] = true
            items[#items + 1] = text
        end
    end
    return items
end

local function first_table_entry(value)
    if type(value) ~= "table" then
        return nil
    end

    for _, item in ipairs(value) do
        return item
    end

    return nil
end

local function first_array_value(value)
    if type(value) ~= "table" then
        return nil
    end

    for _, item in ipairs(value) do
        local candidate = first_nonempty(item)
        if candidate ~= nil then
            return candidate
        end
    end

    return nil
end

local function license_to_string(value)
    value = json_value(value)
    if type(value) == "string" then
        return trim(value)
    end

    if type(value) ~= "table" then
        return nil
    end

    local items = as_string_array(value)
    if #items > 0 then
        return table.concat(items, ", ")
    end

    return nil
end

local function extract_formula_installed_version(formula)
    local installed = json_value(formula.installed)
    if type(installed) == "table" then
        for _, item in ipairs(installed) do
            if type(item) == "table" then
                local version = first_nonempty(json_value(item.version))
                if version ~= nil then
                    return version
                end
            elseif type(item) == "string" then
                return trim(item)
            end
        end
    end

    return first_nonempty(json_value(formula.current_version), json_value(formula.linked_keg))
end

local function extract_cask_installed_version(cask)
    local installed = json_value(cask.installed)
    if type(installed) == "string" then
        return trim(installed)
    end

    if type(installed) == "table" then
        for _, item in ipairs(installed) do
            if type(item) == "table" then
                local version = first_nonempty(json_value(item.version), json_value(item.installed))
                if version ~= nil then
                    return version
                end
            elseif type(item) == "string" then
                return trim(item)
            end
        end
    end

    return first_nonempty(json_value(cask.current_version), first_array_value(json_value(cask.installed_versions)))
end

local function extract_formula_latest_version(formula)
    local versions = json_value(formula.versions)
    return first_nonempty(
        type(versions) == "table" and json_value(versions.stable) or nil,
        json_value(formula.version),
        first_array_value(json_value(formula.versions)),
        extract_formula_installed_version(formula)
    )
end

local function extract_cask_latest_version(cask)
    return first_nonempty(
        json_value(cask.version),
        first_array_value(json_value(cask.versions)),
        json_value(cask.current_version),
        extract_cask_installed_version(cask)
    )
end

local function record_is_outdated(record, installed_version, latest_version)
    if json_value(record.outdated) == true then
        return true
    end

    if installed_version == nil or latest_version == nil or latest_version == "latest" then
        return false
    end

    return installed_version ~= latest_version
end

local function build_status(installed, outdated)
    if outdated then
        return "outdated"
    end

    if installed then
        return "installed"
    end

    return "available"
end

local function extract_cask_dependencies(cask)
    local dependencies = {}
    local depends_on = json_value(cask.depends_on)
    if type(depends_on) ~= "table" then
        return dependencies
    end

    append_all(dependencies, as_string_array(json_value(depends_on.formula)))
    append_all(dependencies, as_string_array(json_value(depends_on.cask)))
    return unique_strings(dependencies)
end

local function extract_cask_binaries(cask)
    local binaries = {}
    local seen = {}
    local artifacts = json_value(cask.artifacts)
    if type(artifacts) ~= "table" then
        return binaries
    end

    for _, artifact in ipairs(artifacts) do
        if type(artifact) == "table" then
            local binary = json_value(artifact.binary)
            if type(binary) == "string" then
                local name = trim(binary)
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    binaries[#binaries + 1] = name
                end
            elseif type(binary) == "table" then
                local name = first_nonempty(json_value(binary[1]), json_value(binary.source), json_value(binary.name))
                if name ~= nil and not seen[name] then
                    seen[name] = true
                    binaries[#binaries + 1] = name
                end
            end
        end
    end

    return binaries
end

local function map_formula_to_package_info(formula)
    local name = first_nonempty(json_value(formula.name), json_value(formula.full_name))
    local version = first_nonempty(extract_formula_installed_version(formula), extract_formula_latest_version(formula))
    local latest_version = first_nonempty(extract_formula_latest_version(formula), version)
    local installed = type(json_value(formula.installed)) == "table" and #json_value(formula.installed) > 0
    local outdated = record_is_outdated(formula, version, latest_version)

    return {
        name = name,
        packageId = name ~= nil and (PLUGIN_ID .. "/formula/" .. name) or nil,
        version = version,
        latestVersion = latest_version,
        installed = installed,
        status = build_status(installed, outdated),
        summary = first_nonempty(json_value(formula.desc)),
        description = first_nonempty(json_value(formula.desc)),
        homepage = first_nonempty(json_value(formula.homepage)),
        repository = first_nonempty(json_value(formula.tap), "homebrew/core"),
        license = license_to_string(json_value(formula.license)),
        dependencies = as_string_array(json_value(formula.dependencies)),
        binaries = as_string_array(json_value(formula.binaries)),
        packageType = "formula",
        type = "package",
        extraFields = {
            packageType = "formula",
        },
    }
end

local function map_cask_to_package_info(cask)
    local token = first_nonempty(json_value(cask.token), json_value(cask.full_token), first_array_value(json_value(cask.name)))
    local version = first_nonempty(extract_cask_installed_version(cask), extract_cask_latest_version(cask))
    local latest_version = first_nonempty(extract_cask_latest_version(cask), version)
    local installed = extract_cask_installed_version(cask) ~= nil
    local outdated = record_is_outdated(cask, version, latest_version)

    return {
        name = token,
        packageId = token ~= nil and (PLUGIN_ID .. "/cask/" .. token) or nil,
        version = version,
        latestVersion = latest_version,
        installed = installed,
        status = build_status(installed, outdated),
        summary = first_nonempty(json_value(cask.desc)),
        description = first_nonempty(json_value(cask.desc)),
        homepage = first_nonempty(json_value(cask.homepage)),
        repository = first_nonempty(json_value(cask.tap), "homebrew/cask"),
        license = license_to_string(json_value(cask.license)),
        dependencies = extract_cask_dependencies(cask),
        binaries = extract_cask_binaries(cask),
        packageType = "cask",
        type = "package",
        extraFields = {
            packageType = "cask",
        },
    }
end

local function map_record_to_package_info(record, package_type)
    if package_type == "cask" then
        return map_cask_to_package_info(record)
    end

    return map_formula_to_package_info(record)
end

local function fetch_info_json(context, names, options)
    options = options or {}
    local args = { "info", "--json=v2" }

    if options.installed then
        args[#args + 1] = "--installed"
    end

    if options.packageType == "formula" then
        args[#args + 1] = "--formula"
    elseif options.packageType == "cask" then
        args[#args + 1] = "--cask"
    end

    for _, name in ipairs(names or {}) do
        args[#args + 1] = name
    end

    return run_brew_json(context, args, {
        allow_missing = options.allow_missing,
        exec_runner = options.exec_runner,
        brew_binary = options.brew_binary,
    })
end

local function pick_matching_formula(formulae, requested_name)
    requested_name = trim(requested_name)
    for _, formula in ipairs(formulae or {}) do
        local name = first_nonempty(json_value(formula.name), json_value(formula.full_name))
        if requested_name == "" or name == requested_name then
            return formula
        end
    end

    return first_table_entry(formulae)
end

local function pick_matching_cask(casks, requested_name)
    requested_name = trim(requested_name)
    for _, cask in ipairs(casks or {}) do
        local token = first_nonempty(json_value(cask.token), json_value(cask.full_token))
        if requested_name == "" or token == requested_name then
            return cask
        end
    end

    return first_table_entry(casks)
end

local function detect_requested_type(pkg)
    local direct = first_nonempty(read_field(pkg, "packageType"), read_nested_field(pkg, "extraFields", "packageType"))
    if direct == "formula" or direct == "cask" then
        return direct
    end

    local package_type = first_nonempty(read_nested_field(pkg, "flags", "packageType"))
    if package_type == "formula" or package_type == "cask" then
        return package_type
    end

    return nil
end

local function resolve_requested_package(context, pkg, options)
    options = options or {}
    local requested_name = first_nonempty(
        read_field(pkg, "name"),
        read_field(pkg, "packageId")
    )

    if requested_name == nil then
        return nil, "missing package name"
    end

    local requested_type = detect_requested_type(pkg)
    local info, err = fetch_info_json(context, { requested_name }, {
        allow_missing = true,
        packageType = requested_type,
        exec_runner = options.exec_runner,
        brew_binary = options.brew_binary,
    })
    if info == nil then
        return nil, err
    end

    local formula = pick_matching_formula(json_value(info.formulae), requested_name)
    local cask = pick_matching_cask(json_value(info.casks), requested_name)

    local package_type = requested_type
    local record = nil
    if requested_type == "formula" then
        record = formula
    elseif requested_type == "cask" then
        record = cask
    elseif formula ~= nil and cask ~= nil then
        package_type = "formula"
        record = formula
        call_logger(context, "info", "homebrew package '" .. requested_name .. "' exists as formula and cask, preferring formula")
    elseif formula ~= nil then
        package_type = "formula"
        record = formula
    elseif cask ~= nil then
        package_type = "cask"
        record = cask
    end

    if record == nil or package_type == nil then
        return nil, "package not found: " .. requested_name
    end

    local mapped = map_record_to_package_info(record, package_type)
    local merged = shallow_copy(type(pkg) == "table" and pkg or {})
    for key, value in pairs(mapped) do
        merged[key] = value
    end

    merged.extraFields = merge_extra_fields(read_field(pkg, "extraFields"), mapped.extraFields)
    return merged, nil
end

local function missing_due_to_action(pkg, resolved)
    local action = lower(read_field(pkg, "action") or "")

    if action == "remove" then
        return resolved.installed == true
    end

    if action == "update" then
        return resolved.status == "outdated"
    end

    return resolved.installed ~= true
end

local function split_by_package_type(packages)
    local formulae = {}
    local casks = {}

    for _, pkg in ipairs(packages or {}) do
        if pkg.packageType == "cask" then
            casks[#casks + 1] = pkg
        else
            formulae[#formulae + 1] = pkg
        end
    end

    return formulae, casks
end

local function package_names(packages)
    local names = {}
    for _, pkg in ipairs(packages or {}) do
        local name = first_nonempty(pkg.name)
        if name ~= nil then
            names[#names + 1] = name
        end
    end
    return names
end

local function run_brew_operation(context, brew_binary, step_label, args, success_event, payload)
    begin_step(context, step_label)
    local result, err = run_brew(context, args, { brew_binary = brew_binary })
    if result == nil then
        tx_failed(context, err)
        return false
    end

    if not result.success then
        tx_failed(context, first_nonempty(result.stderr, result.stdout, step_label .. " failed"))
        return false
    end

    emit_event(context, success_event, payload)
    return true
end

local function collect_packages_from_info(info)
    local items = {}

    for _, formula in ipairs(json_value(info.formulae) or {}) do
        items[#items + 1] = map_formula_to_package_info(formula)
    end

    for _, cask in ipairs(json_value(info.casks) or {}) do
        items[#items + 1] = map_cask_to_package_info(cask)
    end

    return items
end

local function parse_search_output(raw)
    local items = {}
    local seen = {}

    for line in tostring(raw or ""):gmatch("[^\r\n]+") do
        if line:match("^==>") == nil then
            for token in line:gmatch("%S+") do
                local name = trim(token)
                if name ~= "" and not seen[name] then
                    seen[name] = true
                    items[#items + 1] = name
                end
            end
        end
    end

    return items
end

local function fetch_search_results(context, brew_binary, prompt, package_type)
    local result, err = run_brew(context, { "search", package_type == "formula" and "--formula" or "--cask", prompt }, {
        brew_binary = brew_binary,
    })
    if result == nil then
        return nil, err
    end

    if not result.success and trim(result.stdout) == "" and trim(result.stderr) ~= "" then
        return nil, trim(result.stderr)
    end

    local names = parse_search_output(result.stdout)
    if #names == 0 then
        return {}, nil
    end

    local info, info_error = fetch_info_json(context, names, {
        packageType = package_type,
        allow_missing = true,
        brew_binary = brew_binary,
    })
    if info == nil then
        return nil, info_error
    end

    if package_type == "formula" then
        local items = {}
        for _, formula in ipairs(json_value(info.formulae) or {}) do
            items[#items + 1] = map_formula_to_package_info(formula)
        end
        return items, nil
    end

    local items = {}
    for _, cask in ipairs(json_value(info.casks) or {}) do
        items[#items + 1] = map_cask_to_package_info(cask)
    end
    return items, nil
end

plugin.fileExtensions = {}

function plugin.getName()
    return PLUGIN_NAME
end

function plugin.getVersion()
    return PLUGIN_VERSION
end

function plugin.getRequirements()
    return {}
end

function plugin.getCategories()
    return { "Package Manager", "Homebrew", "Wrapper" }
end

function plugin.getMissingPackages(packages)
    local items = packages or {}
    local exec_runner = run_global
    local brew_binary = detect_brew_binary(exec_runner)
    if brew_binary == nil then
        local missing = {}
        for _, pkg in ipairs(items) do
            local action = lower(read_field(pkg, "action") or "")
            if action == "remove" or action == "update" then
            else
                missing[#missing + 1] = pkg
            end
        end
        return missing
    end

    local missing = {}
    for _, pkg in ipairs(items) do
        local resolved = resolve_requested_package(nil, pkg, {
            exec_runner = exec_runner,
            brew_binary = brew_binary,
        })
        if resolved == nil or missing_due_to_action(pkg, resolved) then
            missing[#missing + 1] = pkg
        end
    end

    return missing
end

function plugin.install(context, packages)
    local requested = packages or {}
    if #requested == 0 then
        return true
    end

    local brew_binary, bootstrap_error = ensure_brew_installed(context)
    if brew_binary == nil then
        tx_failed(context, first_nonempty(bootstrap_error, "homebrew bootstrap failed"))
        return false
    end

    local resolved = {}
    for _, pkg in ipairs(requested) do
        local item, err = resolve_requested_package(context, pkg, { brew_binary = brew_binary })
        if item == nil then
            emit_event(context, "unavailable", {
                name = first_nonempty(read_field(pkg, "name"), read_field(pkg, "packageId")),
                reason = err,
            })
            tx_failed(context, err)
            return false
        end
        resolved[#resolved + 1] = item
    end

    local formulae, casks = split_by_package_type(resolved)
    if #formulae > 0 then
        local ok = run_brew_operation(
            context,
            brew_binary,
            "install homebrew formulae",
            { "install", unpack_values(package_names(formulae)) },
            "installed",
            formulae
        )
        if not ok then
            return false
        end
    end

    if #casks > 0 then
        local ok = run_brew_operation(
            context,
            brew_binary,
            "install homebrew casks",
            { "install", "--cask", unpack_values(package_names(casks)) },
            "installed",
            casks
        )
        if not ok then
            return false
        end
    end

    tx_success(context)
    return true
end

function plugin.installLocal(context, path)
    begin_step(context, "install local homebrew artifact")
    tx_failed(context, "homebrew local installs are not supported")
    emit_event(context, "unavailable", {
        path = path,
        reason = "local-install-unsupported",
    })
    return false
end

function plugin.remove(context, packages)
    local requested = packages or {}
    if #requested == 0 then
        return true
    end

    local brew_binary = detect_brew_binary(make_exec_runner(context))
    if brew_binary == nil then
        emit_event(context, "unavailable", { reason = "homebrew-not-installed" })
        tx_failed(context, "homebrew not installed")
        return false
    end

    local resolved = {}
    for _, pkg in ipairs(requested) do
        local item, err = resolve_requested_package(context, pkg, { brew_binary = brew_binary })
        if item == nil then
            emit_event(context, "unavailable", {
                name = first_nonempty(read_field(pkg, "name"), read_field(pkg, "packageId")),
                reason = err,
            })
            tx_failed(context, err)
            return false
        end
        resolved[#resolved + 1] = item
    end

    local formulae, casks = split_by_package_type(resolved)
    if #formulae > 0 then
        local ok = run_brew_operation(
            context,
            brew_binary,
            "remove homebrew formulae",
            { "uninstall", unpack_values(package_names(formulae)) },
            "deleted",
            formulae
        )
        if not ok then
            return false
        end
    end

    if #casks > 0 then
        local ok = run_brew_operation(
            context,
            brew_binary,
            "remove homebrew casks",
            { "uninstall", "--cask", unpack_values(package_names(casks)) },
            "deleted",
            casks
        )
        if not ok then
            return false
        end
    end

    tx_success(context)
    return true
end

function plugin.update(context, packages)
    local requested = packages or {}
    if #requested == 0 then
        return true
    end

    local brew_binary = detect_brew_binary(make_exec_runner(context))
    if brew_binary == nil then
        emit_event(context, "unavailable", { reason = "homebrew-not-installed" })
        tx_failed(context, "homebrew not installed")
        return false
    end

    local resolved = {}
    for _, pkg in ipairs(requested) do
        local item, err = resolve_requested_package(context, pkg, { brew_binary = brew_binary })
        if item == nil then
            emit_event(context, "unavailable", {
                name = first_nonempty(read_field(pkg, "name"), read_field(pkg, "packageId")),
                reason = err,
            })
            tx_failed(context, err)
            return false
        end
        resolved[#resolved + 1] = item
    end

    local formulae, casks = split_by_package_type(resolved)
    if #formulae > 0 then
        local ok = run_brew_operation(
            context,
            brew_binary,
            "update homebrew formulae",
            { "upgrade", unpack_values(package_names(formulae)) },
            "updated",
            formulae
        )
        if not ok then
            return false
        end
    end

    if #casks > 0 then
        local ok = run_brew_operation(
            context,
            brew_binary,
            "update homebrew casks",
            { "upgrade", "--cask", unpack_values(package_names(casks)) },
            "updated",
            casks
        )
        if not ok then
            return false
        end
    end

    tx_success(context)
    return true
end

function plugin.list(context)
    local brew_binary = detect_brew_binary(make_exec_runner(context))
    if brew_binary == nil then
        emit_event(context, "unavailable", { reason = "homebrew-not-installed" })
        return {}
    end

    local info, err = fetch_info_json(context, {}, {
        installed = true,
        brew_binary = brew_binary,
    })
    if info == nil then
        emit_event(context, "unavailable", { reason = err })
        return {}
    end

    local items = collect_packages_from_info(info)
    emit_event(context, "listed", items)
    return items
end

function plugin.outdated(context)
    local brew_binary = detect_brew_binary(make_exec_runner(context))
    if brew_binary == nil then
        emit_event(context, "unavailable", { reason = "homebrew-not-installed" })
        return {}
    end

    local info, err = run_brew_json(context, { "outdated", "--json=v2" }, {
        brew_binary = brew_binary,
    })
    if info == nil then
        emit_event(context, "unavailable", { reason = err })
        return {}
    end

    local items = collect_packages_from_info(info)
    emit_event(context, "outdated", items)
    return items
end

function plugin.search(context, prompt)
    if trim(prompt) == "" then
        local empty = {}
        emit_event(context, "searched", empty)
        return empty
    end

    local brew_binary = detect_brew_binary(make_exec_runner(context))
    if brew_binary == nil then
        emit_event(context, "unavailable", { reason = "homebrew-not-installed" })
        return {}
    end

    local formulae, formula_error = fetch_search_results(context, brew_binary, prompt, "formula")
    if formulae == nil then
        emit_event(context, "unavailable", { reason = formula_error })
        return {}
    end

    local casks, cask_error = fetch_search_results(context, brew_binary, prompt, "cask")
    if casks == nil then
        emit_event(context, "unavailable", { reason = cask_error })
        return {}
    end

    local items = {}
    append_all(items, formulae)
    append_all(items, casks)
    emit_event(context, "searched", items)
    return items
end

function plugin.info(context, name)
    local package_name = trim(name)
    if package_name == "" then
        emit_event(context, "unavailable", { reason = "missing-package-name" })
        return {}
    end

    local brew_binary = detect_brew_binary(make_exec_runner(context))
    if brew_binary == nil then
        emit_event(context, "unavailable", { reason = "homebrew-not-installed" })
        return {}
    end

    local item, err = resolve_requested_package(context, { name = package_name }, { brew_binary = brew_binary })
    if item == nil then
        emit_event(context, "unavailable", {
            name = package_name,
            reason = err,
        })
        return {}
    end

    emit_event(context, "informed", item)
    return item
end

function plugin.init()
    return true
end

function plugin.shutdown()
    return true
end

function plugin.resolvePackage(context, package)
    local brew_binary = detect_brew_binary(make_exec_runner(context))
    if brew_binary == nil then
        return nil
    end

    local item = resolve_requested_package(context, package, { brew_binary = brew_binary })
    return item
end

function plugin.getSecurityMetadata()
    return {
        role = "package-manager",
        capabilities = { "exec", "network" },
        ecosystemScopes = { "homebrew" },
        writeScopes = {
            { kind = "temp" },
            { kind = "user-home-subpath", value = ".cache/Homebrew" },
            { kind = "user-home-subpath", value = ".linuxbrew" },
        },
        networkScopes = {
            { host = "raw.githubusercontent.com", scheme = "https", pathPrefix = "/Homebrew/install/" },
        },
        privilegeLevel = "user",
    }
end

return plugin
