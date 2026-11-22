-- re_executor.lua (REFramework, RE4 Remake)

local executor = {
    code_buffer = 're.msg("Test z executora amadeusz RE")',
    last_status = "Gotowy",
    history = {},
    text = "Kroki: 1) Snapshot A  2) strzel 1-3 razy (BEZ PRZELADOWYWANIA)  3) Snapshot B  4) Infinite Ammo",
}

local function push_history(entry)
    table.insert(executor.history, 1, entry)
    if #executor.history > 15 then table.remove(executor.history) end
end

function executor.run(chunk_str)
    if not chunk_str or chunk_str:match("^%s*$") then
        executor.last_status = "Błąd: pusty kod"
        return false
    end
    local fn, compile_err = load(chunk_str, "REExecutorChunk", "t", _G)
    if not fn then
        executor.last_status = "Błąd składni: " .. tostring(compile_err)
        push_history("[ERR] " .. tostring(compile_err))
        return false
    end
    local ok, runtime_err = pcall(fn)
    if not ok then
        executor.last_status = "Błąd wykonania: " .. tostring(runtime_err)
        push_history("[ERR] " .. tostring(runtime_err))
        return false
    end
    executor.last_status = "OK — wykonano pomyślnie"
    push_history("[OK] " .. chunk_str:gsub("\n", " "))
    return true
end

_G.REExec = executor

-- ===== AUTO-WYKRYWANIE AMUNICJI =====
local snapA = nil
local frozen = {}      -- lista {item=i, path={...}, value=wartosc}
local infinite = false

local function skip_type(n)
    return n:find("Action`", 1, true) or n:find("System.Guid", 1, true)
        or n:find("ContextID", 1, true) or n:find("Delegate", 1, true)
        or n:find("Context", 1, true)
end

local function get_items()
    local inv = sdk.get_managed_singleton("chainsaw.InventoryManager")
    if not inv then return nil end
    local entries = inv:get_field("_ControllerTable"):get_field("_entries"):get_elements()
    for _, e in ipairs(entries) do
        local v = e:get_field("value")
        if v then
            local ci = v:get_field("<_CsInventory>k__BackingField")
            if ci then
                return ci:get_field("_InventoryItems"):get_field("_items"):get_elements()
            end
        end
    end
    return nil
end

local function collect(obj, path, depth, cb)
    if obj == nil or depth <= 0 then return end
    local okt, t = pcall(function() return obj:get_type_definition() end)
    if not okt or not t then return end
    if skip_type(t:get_full_name()) then return end
    local tt = t
    while tt do
        local pn = tt:get_full_name()
        if pn == "System.Object" or pn:find("^via%.") then break end
        for _, f in ipairs(tt:get_fields()) do
            if not f:is_static() then
                local fname = f:get_name()
                local okv, v = pcall(function() return obj:get_field(fname) end)
                if okv and v ~= nil then
                    local ty = type(v)
                    local np = {}
                    for i, p in ipairs(path) do np[i] = p end
                    np[#np + 1] = fname
                    if ty == "number" then
                        cb(np, v)
                    elseif ty == "userdata" then
                        collect(v, np, depth - 1, cb)
                    end
                end
            end
        end
        tt = tt:get_parent_type()
    end
end

local function snapshot()
    local snap = {}
    local items = get_items()
    if not items then return nil end
    for i, it in ipairs(items) do
        if it ~= nil then
            collect(it, {}, 3, function(path, val)
                snap[i .. "|" .. table.concat(path, ".")] = { item = i, path = path, value = val }
            end)
        end
    end
    return snap
end

local function set_value(entry, value)
    local items = get_items()
    local o = items and items[entry.item]
    if not o then return end
    for k = 1, #entry.path - 1 do
        o = o:get_field(entry.path[k])
        if o == nil then return end
    end
    o:set_field(entry.path[#entry.path], value)
end

local function do_snapA()
    local ok, res = pcall(snapshot)
    if ok and res then
        snapA = res
        local n = 0
        for _ in pairs(res) do n = n + 1 end
        executor.text = "Snapshot A zapisany (" .. n .. " liczb).\nTeraz STRZEL 1-3 razy (bez przeladowania) i kliknij Snapshot B."
    else
        executor.text = "BLAD Snapshot A: " .. tostring(res)
    end
end

local function do_snapB()
    if not snapA then executor.text = "Najpierw Snapshot A" return end
    local ok, snapB = pcall(snapshot)
    if not ok or not snapB then executor.text = "BLAD Snapshot B: " .. tostring(snapB) return end
    local out = {}
    frozen = {}
    for key, a in pairs(snapA) do
        local b = snapB[key]
        if b and math.type and math.type(a.value) == "integer" or (b and a.value == math.floor(a.value)) then
            if b and b.value < a.value and (a.value - b.value) <= 10 then
                out[#out + 1] = key .. " : " .. a.value .. " -> " .. b.value
                frozen[#frozen + 1] = { item = a.item, path = a.path, value = a.value }
            end
        end
    end
    if #out == 0 then
        executor.text = "Nic nie spadlo. Upewnij sie, ze miedzy A i B oddales strzal z wyciagnietej broni."
    else
        executor.text = "Pola, ktore spadly po strzale (to powinna byc amunicja):\n" .. table.concat(out, "\n")
            .. "\n\nKliknij Infinite Ammo ON/OFF."
    end
    for _, l in ipairs(out) do log.info("[AMMO] " .. l) end
end

re.on_frame(function()
    if infinite and #frozen > 0 then
        for _, e in ipairs(frozen) do pcall(set_value, e, e.value) end
    end
end)

-- ===== INTERFEJS =====
re.on_draw_ui(function()
    if imgui.begin_window("RE Lua Executor", true, 0) then
        local ok, err = pcall(function()
            imgui.text("Kod Lua:")
            local changed, new_code = imgui.input_text_multiline(
                "##kod", executor.code_buffer, Vector2f.new(520, 60)
            )
            if changed then executor.code_buffer = new_code end

            if imgui.button("Wykonaj") then executor.run(executor.code_buffer) end
            imgui.same_line()
            if imgui.button("Wyczyść bufor") then executor.code_buffer = "" end

            imgui.separator()
            if imgui.button("1. Snapshot A") then do_snapA() end
            imgui.same_line()
            if imgui.button("2. Snapshot B") then do_snapB() end
            imgui.same_line()
            if imgui.button("Infinite Ammo ON/OFF") then
                if #frozen == 0 then
                    executor.text = "Najpierw zrob Snapshot A, strzel, Snapshot B."
                else
                    infinite = not infinite
                end
            end
            imgui.text("Infinite Ammo: " .. (infinite and "ON" or "OFF"))
            imgui.text("Status: " .. executor.last_status)
            imgui.input_text_multiline("##out", executor.text, Vector2f.new(520, 220))
        end)
        if not ok then executor.last_status = "Błąd UI: " .. tostring(err) end
        imgui.end_window()
    end
end)