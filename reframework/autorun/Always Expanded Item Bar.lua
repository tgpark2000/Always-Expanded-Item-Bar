local fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall = fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall
local MOD_TITLE   = "Always Expanded Item Bar"
local CONFIG_FILE = "Always_Expanded_Item_Bar.json"
local DELAY       = { MIN = 0.2, MAX = 2.0 }
local config      = { enabled = true, closingDelay = 0.50, isAutoSwitchEnabled = false }
local oldConfig

local function arrayIsEqual(a, b)
    if (type(a) ~= "table") or (type(b) ~= "table") then return false end
    if #a ~= #b                                     then return false end
    for key, value in pairs(a) do
        if type(value) == "table" then 
            if not arrayIsEqual(value, b[key]) then return false end
        elseif b[key]  ~= value                then return false end
    end
    for key in pairs(b) do 
        if a[key] == nil then return false end
    end
    return true
end

local function arrayDeepCopy(from)
    local ary = {}
    if not from              then return ary  end
    if type(from) ~= "table" then return from end
    for key, value in pairs(from) do 
        ary[key] = (type(value) == "table") and arrayDeepCopy(value) or value
    end
    return ary
end

local function saveConfig(force)
    if (not force) and ((not oldConfig) or arrayIsEqual(config, oldConfig)) then return end  
    json.dump_file(CONFIG_FILE, config)
    oldConfig = arrayDeepCopy(config)
end

local function loadConfig()
    local loaded = json.load_file(CONFIG_FILE)
    if not loaded then saveConfig(true) return end

    -- v1.1에서 변수명 변경으로 구버전 세이브파일 마이그레이션
    if loaded.closingDelays and type(loaded.closingDelays) == "number" then 
        if loaded.closingDelay == nil then loaded.closingDelay = loaded.closingDelays end
        loaded.closingDelays = nil
    end
    -- 변수 유효성 체크
    if type(loaded.enabled)             ~= "boolean" then loaded.enabled             = true  end
    if type(loaded.closingDelay)        ~= "number"  then loaded.closingDelay        = 0.50  end
    if type(loaded.isAutoSwitchEnabled) ~= "boolean" then loaded.isAutoSwitchEnabled = false end
    
    loaded.closingDelay = math.min(math.max(DELAY.MIN, loaded.closingDelay), DELAY.MAX)
    config              = arrayDeepCopy(loaded)
    oldConfig           = arrayDeepCopy(loaded)
end loadConfig()

local lastActiveTime = 0
local SLOT_ITEM_USE  = sdk.find_type_definition("app.GUI020006PartsAllSlider"):get_field("SLOT_ITEM_USE"):get_data()
sdk.hook(sdk.find_type_definition("app.GUI020006PartsAllSlider"):get_method("callbackOther(ace.GUIDef.BUTTON_SLOT, via.gui.Control, via.gui.SelectItem, System.UInt32)"), function(args) if not config.enabled then return sdk.PreHookResult.CALL_ORIGINAL end
    thread.get_hook_storage().inputButtonSlot = sdk.to_int64(args[3])
return sdk.PreHookResult.CALL_ORIGINAL end, function() if not config.enabled then return end
    local storage           = thread.get_hook_storage()
    local inputButtonSlot   = storage.inputButtonSlot
    lastActiveTime          = (inputButtonSlot ~= SLOT_ITEM_USE) and os.clock() or 0
    storage.inputButtonSlot = nil
end)

sdk.hook(sdk.find_type_definition("app.GUI020006PartsSlider"):get_method("callbackOther(ace.GUIDef.BUTTON_SLOT, via.gui.Control, via.gui.SelectItem, System.UInt32)"), function(args) if not config.enabled then return sdk.PreHookResult.CALL_ORIGINAL end
    local thisPtr  = sdk.to_managed_object(args[2])
    local ownerGui = thisPtr:get_MyOwner()
    if not ownerGui then return sdk.PreHookResult.CALL_ORIGINAL end

    if not ownerGui:get_IsAllSliderMode() then
        lastActiveTime = os.clock()
        ownerGui:startAllSlider()
        return sdk.PreHookResult.SKIP_ORIGINAL 
    end
return sdk.PreHookResult.CALL_ORIGINAL end)

local DEVICE_GAME_CONTROLLER = sdk.find_type_definition("ace.GUIDef.INPUT_DEVICE"):get_field("PAD"):get_data()
sdk.hook(sdk.find_type_definition("app.GUI020006"):get_method("endAllSlider()"), function(args) 
    local thisPtr = sdk.to_managed_object(args[2])
    if not thisPtr:get_IsAllSliderMode() then return sdk.PreHookResult.CALL_ORIGINAL end
    local isGameController = (thisPtr:get__LastInputDevice() == DEVICE_GAME_CONTROLLER)
    if isGameController then           if thisPtr:isOpenItemSlider() then return sdk.PreHookResult.SKIP_ORIGINAL end  -- For Game Controller
    elseif ((os.clock() - lastActiveTime) < config.closingDelay)     then return sdk.PreHookResult.SKIP_ORIGINAL end  -- For Keyboard & Mouse
return sdk.PreHookResult.CALL_ORIGINAL end)

local INIT_ALL = sdk.find_type_definition("app.GUI020006.REQUEST_TYPE"):get_field("INIT_ALL"):get_data()
sdk.hook(sdk.find_type_definition("app.GUI020006PartsSlider"):get_method("updateText(app.ItemDef.ID, System.Int16, System.Boolean)"), function(args) if not config.enabled or not config.isAutoSwitchEnabled then return sdk.PreHookResult.CALL_ORIGINAL end
    local itemId  = sdk.to_int64(args[3]) & 0xFFFF
    local itemNum = sdk.to_int64(args[4]) & 0xFF
    if itemId ~= 0 and itemNum ~= 0 then return sdk.PreHookResult.CALL_ORIGINAL end

    local thisPtr           = sdk.to_managed_object(args[2])
    local partsAllSlider    = thisPtr:get__AllSlider()
    local ownerGui          = thisPtr:get_MyOwner()
    local currentActiveItem = partsAllSlider:getCurrentItem()
    if not currentActiveItem then return sdk.PreHookResult.CALL_ORIGINAL end
    
    local gridPartsList     = partsAllSlider:get_field("<_GridParts>k__BackingField")
    local current2D         = currentActiveItem:get__BaseItem():get_GlobalIndex2D()
    if not current2D or not gridPartsList then return sdk.PreHookResult.CALL_ORIGINAL end

    local nextItemId      = nil
    local listCount       = gridPartsList:get_Count() or 0
    local searchCondition = {{ 0, -1}, { 0, 1}, { -1, 0 }, { 1, 0 }}  -- up, down, left, right
    for n, vec2 in ipairs(searchCondition) do
        local nextX, nextY = current2D.x + vec2[1], current2D.y + vec2[2]
        for i = 0, listCount - 1 do
            local item = gridPartsList:get_Item(i)
            local p2D  = item and item:get__BaseItem():get_GlobalIndex2D()
            if p2D and p2D.x == nextX and p2D.y == nextY then
                nextItemId = item:getItemId()
                break
            end
        end
        if nextItemId then break end
    end    

    if nextItemId and nextItemId ~= 0 then
        ownerGui:set_SelectedItemId(nextItemId)
        ownerGui:executePouchChange(INIT_ALL, nextItemId)
        return sdk.PreHookResult.SKIP_ORIGINAL        
    end
return sdk.PreHookResult.CALL_ORIGINAL end)

re.on_config_save(saveConfig)
re.on_draw_ui(function() if not imgui.tree_node(MOD_TITLE) then return end
    local changed, value
    imgui.spacing()
    changed, config.enabled = imgui.checkbox("Enable", config.enabled)
    imgui.spacing()

    imgui.push_item_width(220)
    imgui.text("For Keyboard & Mouse:") 
    changed, value = imgui.slider_float("##ClosingDelay", config.closingDelay, DELAY.MIN, DELAY.MAX, "Close Delay: %.2fs")  
    if changed then config.closingDelay = math.floor((value + 0.005) * 100) / 100 end
    imgui.pop_item_width()
    imgui.spacing()

    changed, config.isAutoSwitchEnabled = imgui.checkbox("Auto-switch to next item when empty.", config.isAutoSwitchEnabled)
    if imgui.is_item_hovered() then imgui.set_tooltip("Auto-Switch Priority:\n 1. Upper slot item\n 2. Lower slot item\n 3. Left slot item\n 4. Right slot item") end
    imgui.spacing()
imgui.tree_pop() end)
