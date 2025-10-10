---@diagnostic disable: redundant-parameter
local pluginName = select(1, ...)
local componentName = select(2, ...)
local signalTable = select(3, ...)
local myHandle = select(4, ...)

-- CONSTANTS
local PLUGIN_NAME = 'SpeedtoTime'
local PLUGIN_VERSION = 'ALPHA 0.1.1'
local UI_CMD_ICON_NAME = PLUGIN_NAME .. 'Icon'
local UI_MENU_NAME = PLUGIN_NAME .. ' Menu'

-- PLUGIN STATE
local pluginAlive = nil
local pluginRunning = false
local pluginError = nil

local presskey = function(key)
  Keyboard(1, "press", key)
  Keyboard(1, "release", key)
end

-- HELPER FUNCTIONS - Global Variables
local function get_global(varName, default)
  return GetVar(GlobalVars(), varName) or default
end

local hasTimeMAtricks = get_global("TM_MasterValue") ~= nil

local function set_global(varName, value)
  SetVar(GlobalVars(), varName, value)
  return value ~= nil
end

-- CONSTANTS - UI Colors, Icons, Corners
local colors = {
  text = {
    white = "Global.Text",
    black = "Global.Darkened",
  },
  background = {
    default = "Overlay.FrameColor",
    dark = "Overlay.Background",
    on = "Global.WarningText",
    off = "Global.Running",
    fade = "ProgLayer.Fade",
    delay = "ProgLayer.Delay",
    transparent25 = "Global.Transparent25",
  },
  button = {
    default = "Button.Background",
    clear = "Button.BackgroundClear",
    please = "Button.BackgroundPlease",
  },
  icon = {
    active = "Button.ActiveIcon",
    inactive = "Button.Icon",
  },
}
local icons = {
  matricks = 'object_matricks',
  star = 'star',
  cross = 'close',
  time = 'object_clock',
}
local corners = {
  none = 'corner0',
  topleft = 'corner1',
  topright = 'corner2',
  bottomleft = 'corner4',
  bottomright = 'corner8',
  top = 'corner3',
  bottom = 'corner12',
  left = 'corner5',
  right = 'corner10',
  all = 'corner15',
}

local function sanitize_text(text)
  text = tostring(text or "")
  if text == "" then return "" end
  -- convert comma to dots
  text = text:gsub(",", ".")
  -- keep only digits and dot
  text = text:gsub("[^%d%.]", "")
  --keep just the first dot
  local fistDotSeen = false
  local cleaned = {}
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "." then
      if not fistDotSeen then
        table.insert(cleaned, c)
        fistDotSeen = true
      end
    else
      table.insert(cleaned, c)
    end
  end
  text = table.concat(cleaned)

  --msut start with a digit, find first digit
  local firstDigit = text:match("%d")
  if not firstDigit then
    return ""
  end

  -- build result
  local digitIndex = text:find(firstDigit, 1, true)
  local afterFirst = text:sub(digitIndex + 1)

  -- ignore any further digits before a possible dot
  local dotPos = afterFirst:find("%.")
  if dotPos then
    --there is a dot after the leading digit
    local decimals = afterFirst:sub(dotPos + 1)
    decimals = decimals:gsub("%.", "")              -- remove any further dots
    decimals = decimals:gsub("[^%d]", ""):sub(1, 2) -- keep only digits, max 2
    if decimals == "" and text:sub(-1) == "." then
      -- user just typed the dot; allow transient
      return firstDigit .. "."
    end
    return firstDigit .. "." .. decimals
  else
    -- no dot, just return leading digits
    return firstDigit
  end
end

local function get_subdir(subdir)
  return (subdir == "CmdLineSection" and GetDisplayByIndex(1).CmdLineSection)
      or (subdir == "ScreenOverlay" and GetDisplayByIndex(1).ScreenOverlay)
end

local function is_valid_ui_item(objname, subdir)
  local dir = get_subdir(subdir)
  if not dir then
    ErrPrintf("subdir not recognized: %s", tostring(subdir))
    return false
  end
  local found = dir:FindRecursive(objname)
  return found ~= nil
end

-- Helper to write a text file
local function write_text_file(path, content)
  local old = ""
  local f = io.open(path, "rb")
  if f then
    old = f:read("*a") or ""; f:close()
  end
  if old == content then return true end
  local wf, err = io.open(path, "wb")
  if not wf then
    ErrPrintf("Failed to write %s: %s", tostring(path), tostring(err))
    return false
  end
  wf:write(content)
  wf:close()
  return true
end

local UI_XML_CONTENT = [[

]]

-- XML MANAGEMENT
-- Generic function to resolve XML files
-- xmlType: "ui"
local function resolve_xml_file(xmlType)
  -- local base = GetPath("temp") or ""
  -- local base = '/Users/juriseiffert/Library/Mobile Documents/com~apple~CloudDocs/Lua Plugins/GMA3/SpeedtoTime'
  local base = 'C:\\Users\\Juri\\iCloudDrive\\Lua Plugins\\GMA3\\SpeedtoTime'
  local dir = base .. "/"
  local filename, content

  if xmlType == "ui" then
    filename = "SpeedtoTime_UI.xml"
    content = UI_XML_CONTENT
  else
    ErrPrintf("Unknown XML type: %s", tostring(xmlType))
    return nil, nil
  end

  local slash = GetPathSeparator()
  local full = dir .. slash .. filename
  if not FileExists(full) then
    local ok = write_text_file(full, content)
    if not ok then
      full = (base .. "/" .. filename)
      write_text_file(full, content)
      dir = base
    end
  end

  -- ui:Import needs directory (with trailing sep) and filename
  local dirWithSep = dir:match("^(.*[/\\])$") and dir or (dir .. "/")
  return dirWithSep, filename
end

function BPM_quartic(normed)
  -- coefficients (highest -> lowest): a4,a3,a2,a1,a0
  local a4 = 1.4782363954528236e-07
  local a3 = -4.7011506911898910e-05
  local a2 = 0.02546732094127444
  local a1 = 0.02565532641182032
  local a0 = -0.015923207227581285
  local y = ((((a4 * normed + a3) * normed + a2) * normed + a1) * normed + a0)
  if y <= 30 then y = 30 end
  if y >= 0 then
    return math.floor(y * 10 + 0.5) / 10
  else
    return math.ceil(y * 10 - 0.5) / 10
  end
end

-- UI ELEMENT CONFIGURATION
-- Generic function to configure UI elements
-- elementType: "button", "checkbox", "textbox", "hold"
local function add_ui_element(name, overlay, elementType, options)
  local el = overlay:FindRecursive(name)
  if not el then
    local typeDesc = elementType == "checkbox" and "Box" or
        elementType == "textbox" and "Textbox" or "Button"
    ErrPrintf("%s not found: %s", typeDesc, tostring(name))
    return false
  end

  el.PluginComponent = myHandle

  -- Handle different element types
  if elementType == "button" or elementType == "checkbox" then
    el.Clicked = options.clicked or ""
  end

  if elementType == "hold" then
    el.MouseDownHold = options.hold or ""
  end

  if elementType == "checkbox" and options.state ~= nil then
    el.State = options.state
  end

  if elementType == "textbox" and options.content ~= nil then
    el.Content = options.content
  end

  if options.enabled ~= nil then
    el.Enabled = options.enabled
  else
    el.Enabled = "Yes"
  end

  return true
end

-- UI CREATION FUNCTIONS
local function create_menu()
  local overlay = GetDisplayByIndex(1).ScreenOverlay
  local ui = overlay:Append('BaseInput')
  ui.SuppressOverlayAutoclose = "Yes"
  ui.AutoClose = "No"
  ui.CloseOnEscape = "Yes"

  local path, filename = resolve_xml_file("ui")
  Printf("Import from " .. tostring(path) .. tostring(filename))
  if not path then
    ErrPrintf("UI XML file not found")
    return
  end

  if not ui:Import(path, filename) then
    ErrPrintf("Failed to import UI XML from %s%s", tostring(path), tostring(filename))
    return
  end

  ui:HookDelete(signalTable.close, ui)

  -- wire up and set initial defaults first
  local buttons = {
    { "PluginOff", "plugin_off" },
    { "PluginOn",  "plugin_on" },
    { "Apply",       "apply" },
  }
  for _, b in ipairs(buttons) do
    if not add_ui_element(b[1], ui, "button", { clicked = b[2] }) then
      ErrPrintf("error at %s", b)
    end
  end

  local checks = {
    { "TM1Toggle", "timing_toggle", 1 },
    { "TM2Toggle", "timing_toggle", 1 },
    { "TM3Toggle", "timing_toggle", 1 },
  }
  for _, c in ipairs(checks) do
    if not add_ui_element(c[1], ui, "checkbox", { clicked = c[2], state = c[3] }) then
      ErrPrintf("error at %s", c)
    end
  end

  local texts = {
    { "SPValue", "text" },    -- no default -> keep existing
    { "TM1Value",    "text", "1" }, { "TM1Rate", "text", "0.25" },
    { "TM2Value", "text", "2" }, { "TM2Rate", "text", "0.5" },
    { "TM3Value", "text", "3" }, { "TM3Rate", "text", "1" },
  }
  for _, t in ipairs(texts) do
    if not add_ui_element(t[1], ui, "textbox", { content = t[3] }) then
      ErrPrintf("error at %s", t)
    end
  end

  local rates = {
    -- { "HT",        "rate_mod",          1 },
    -- { "ResetRate", "reset_overallrate", 1 },
    -- { "DT",        "rate_mod",          1 },
  }

  for _, r in ipairs(rates) do
    if not add_ui_element(r[1], ui, "button", { clicked = r[2] }) then
      ErrPrintf("error at %s", r)
    end
  end

  local plugininfo = {
    { "TitleButton", PLUGIN_NAME,                 icons.time },
    { "Version",     "Version " .. PLUGIN_VERSION },
  }

  for _, p in ipairs(plugininfo) do
    local el = ui:FindRecursive(p[1])
    if el then
      el.Text = p[2] or ""
      if p[3] then
        el.Icon = p[3]
      end
    end
  end

  -- now load saved globals so they override the defaults set above
  --   load_state(ui)
  --   save_state()

  local title = ui:FindRecursive("TitleBar")
  local cb = title:FindRecursive("CheckBox")
  if not hasTimeMAtricks then
    if title then
      cb.Enabled = "No"
      cb.State = 0
      cb.Tooltip = "Get the TimeMAtricks Plugin to sync settings"
    end
  else
    cb.Enabled = "Yes"
    cb.Tooltip = "Use TimeMAtricks settings"
  end
  coroutine.yield(0.1) -- slight delay to ensure UI is ready
end

local function create_CMDlineIcon()
  Printf("Creating CMDline Icon")
  local cmdbar               = GetDisplayByIndex(1).CmdLineSection
  local lastCols             = tonumber(cmdbar:Get("Columns"))
  local cols                 = lastCols + 1
  cmdbar.Columns             = cols
  cmdbar[2][cols].SizePolicy = "Fixed"
  cmdbar[2][cols].Size       = 50

  STIcon                     = cmdbar:Append('Button')
  STIcon.Name                = UI_CMD_ICON_NAME
  STIcon.Anchors             = { left = cols - 2 }
  STIcon.W                   = 49
  STIcon.PluginComponent     = myHandle
  STIcon.Clicked             = 'cmdbar_clicked'
  STIcon.Icon                = icons.time
  STIcon.IconColor           = colors.icon.inactive
  STIcon.Tooltip             = "SpeedtoTime Plugin"

  Tri                        = cmdbar:FindRecursive("RightTriangle")
  if Tri then
    Tri.Anchors = { left = cols - 1 }
  end
end

local function delete_CMDlineIcon()
  if STIcon then
    local cmdbar = GetDisplayByIndex(1).CmdLineSection
    local iconPosition = STIcon.Anchors.left or 0 -- Get the actual position

    -- Remove the icon
    cmdbar:Remove(STIcon:Get("No"))
    STIcon = nil

    -- Decrease column count
    local currentCols = tonumber(cmdbar:Get("Columns"))
    cmdbar.Columns = currentCols - 1

    -- Shift all items that were to the right of the removed icon
    for i = 1, cmdbar:Count() do
      local item = cmdbar:Ptr(i)
      if item and item.Anchors and item.Anchors.left then
        local itemPosition = item.Anchors.left
        if itemPosition > iconPosition then
          item.Anchors = { left = itemPosition - 1 }
        end
      end
    end

    -- The triangle should now be at the last position
    local Tri = cmdbar:FindRecursive("RightTriangle")
    if Tri then
      Tri.Anchors = { left = currentCols - 2 } -- New last column (0-based)
    end
  end
end

signalTable.apply = function(caller)
  -- Printf("Settings Applied")
  --   save_state()
  signalTable.ShowWarning2(caller, "")
  FindNextFocus()
end

signalTable.timing_toggle = function(caller)
  local mapping = {
    TM1Toggle = { "TM1Value", "TM1Rate" },
  }
  local related = mapping[caller.Name] or {}
  local ov = GetDisplayByIndex(1).ScreenOverlay:FindRecursive(UI_MENU_NAME)
  local newState = (caller:Get("State") == 1) and 0 or 1
  caller:Set("State", newState)

  local enable = (newState == 1) and "Yes" or "No"
  for _, name in ipairs(related) do
    local el = ov:FindRecursive(name)
    if el then
      el.Enabled = enable
      if enable == "Yes" and name:match("Value") then
        FindBestFocus(el)
      else
        FindBestFocus(ov)
      end
    end
  end
  --   save_state()
end

signalTable.Confirm = function(caller)
  local overlay = GetDisplayByIndex(1).ScreenOverlay
  if caller == overlay.FindRecursive(UI_MENU_NAME) then
    signalTable.close(caller)
  end
end

signalTable.sanitize = function(caller)
  local before = caller.Content or ""
  local after = before
  
  -- Special validation for SPValue and TMxValue (integer only, no decimals)
  if caller.Name == "SPValue" or caller.Name == "TM1Value" or caller.Name == "TM2Value" or caller.Name == "TM3Value" then
    -- Keep only digits, no dots or other characters
    after = after:gsub("[^%d]", "")
    
    -- Validate ranges if we have a number
    if after ~= "" then
      local num = tonumber(after)
      if num then
        if caller.Name == "SPValue" then
          if num < 1 then
            after = "1"
          elseif num > 16 then
            after = "16"
          end
        else -- TM1Value, TM2Value, TM3Value
          if num < 1 then
            after = "1"
          elseif num > 50 then
            after = "50"
          end
        end
      end
    end
  else
    -- For other fields (Rate fields), apply decimal formatting
    after = sanitize_text(before)
  end
  
  if before ~= after then
    caller.Content = after
    if caller.HasFocus then
      presskey("End")
      if caller.Name == "SPValue" then
        signalTable.ShowWarning(caller, "Speed Master: 1-16")
      elseif caller.Name == "TM1Value" or caller.Name == "TM2Value" or caller.Name == "TM3Value" then
        signalTable.ShowWarning(caller, "TimingMaster: 1-50")
      else
        signalTable.ShowWarning(caller, "Allowed format: x.xx")
      end
    end
  end
end

signalTable.ShowWarning = function(caller, status, creator)
  local ov = GetDisplayByIndex(1).ScreenOverlay:FindRecursive(UI_MENU_NAME)
  local ov2 = GetDisplayByIndex(1).ScreenOverlay:FindRecursive("Settings Menu")
  if ov == caller:Parent():Parent():Parent() then
    local ti = ov.TitleBar.WarningButton
    ti.ShowAnimation(status)
  elseif ov2 == caller:Parent():Parent():Parent() then
    local ti = ov2.TitleBar.WarningButton
    ti.ShowAnimation(status)
  end
  -- ErrPrintf(status)
  if pluginError then
    pluginError = nil
    coroutine.yield(0.2)
    FindNextFocus(true)
  end
end

signalTable.ShowWarning2 = function(caller, status, creator)
  local ov = GetDisplayByIndex(1).ScreenOverlay:FindRecursive(UI_MENU_NAME)
  if ov == caller:Parent():Parent():Parent() then
    local ti = ov:FindRecursive("WarningButton2")
    ti.ShowAnimation(status)
  end
end

signalTable.LineEditSelectAll = function(caller)
  if not caller then return end
  caller:SelectAll()

  local ov = GetDisplayByIndex(1).ScreenOverlay:FindRecursive(UI_MENU_NAME)
  if not ov then return end

  local fieldNames = {
    "TM1Value",
    "TM2Value",
    "TM3Value",
    "TM1Rate",
    "TM2Rate",
    "TM3Rate",
    "SPValue"
  }

  local function isRate(name)
    return name:match("^TM%dRate$")
  end

  for _, name in ipairs(fieldNames) do
    if name ~= caller.Name and not isRate(name) then
      local el = ov:FindRecursive(name)
      if el then
        -- Deselect if it somehow has focus
        if el.HasFocus then el:Deselect() end
        -- Restore unsaved edits back to stored global
        local saved = get_global("ST_" .. name, el.Content or "")
        if (el.Content or "") ~= saved then
          el.Content = saved
          signalTable.ShowWarning(caller, "NOT SAVED! Restored saved value")
        end
      end
    end
  end
end

signalTable.LineEditDeSelect = function(caller)
  caller.Deselect()
  -- save_state()
end

signalTable.ExecuteOnEnter = function(caller, dummy, keyCode)
  if caller.HasFocus and keyCode == Enums.KeyboardCodes.Enter then
    signalTable.LineEditDeSelect(caller)
    do
      local n = caller and caller.Name
      if n == "TM1Value" or n == "TM2Value" or n == "TM3Value" or n == "TM1Rate" or n == "TM2Rate" or n == "TM3Rate" or n == "SPValue" then
        -- save_state()
      end
    end
    if caller.Name == "Apply" then
      signalTable.apply(caller)
      FindNextFocus()
    elseif caller.Name == "Close" then
      signalTable.close(caller)
    else
      FindNextFocus()
    end
  end
end

signalTable.NextFocus = function()
  FindNextFocus()
end

signalTable.cmdbar_clicked = function()
  if not is_valid_ui_item(UI_MENU_NAME, "ScreenOverlay") then
    local ov = GetTopOverlay(1)
    create_menu()
    local ov = GetTopOverlay(1)
    FindBestFocus(ov)
  else
    return
  end
end

signalTable.close = function(caller)
  if caller and caller.Name == "Close" then
    Printf(caller.Name)
    presskey("Escape")
    local ov = GetDisplayByIndex(1).ScreenOverlay
    local menu = ov:FindRecursive(UI_MENU_NAME)
    menu.Visible = "Yes"
  end
end

signalTable.plugin_off = function(caller)
  pluginRunning = false
  local ov = GetDisplayByIndex(1).ScreenOverlay:FindRecursive(UI_MENU_NAME)
  local on = ov:FindRecursive("PluginOn")
  local off = ov:FindRecursive("PluginOff")
  local titleicon = ov:FindRecursive("TitleButton")
  local cmdicon = GetDisplayByIndex(1).CmdLineSection:FindRecursive(UI_CMD_ICON_NAME)
  if not on or not off then return end
  on.BackColor, off.BackColor, on.TextColor, off.TextColor = colors.button.default, colors.button.clear,
      colors.text.white, colors.icon.active
  titleicon.IconColor = "Button.Icon"
  cmdicon.IconColor = "Button.Icon"
end

signalTable.plugin_on = function(caller)
  pluginRunning = true
  local ov = GetDisplayByIndex(1).ScreenOverlay:FindRecursive(UI_MENU_NAME)
  local off = ov:FindRecursive("PluginOff")
  local on = ov:FindRecursive("PluginOn")
  local titleicon = ov:FindRecursive("TitleButton")
  local cmdicon = GetDisplayByIndex(1).CmdLineSection:FindRecursive(UI_CMD_ICON_NAME)
  if not on or not off then return end
  off.BackColor, on.BackColor, off.TextColor, on.TextColor = colors.button.default, colors.button.please,
      colors.text.white, colors.icon.active
  titleicon.IconColor = "Button.ActiveIcon"
  cmdicon.IconColor = "Button.ActiveIcon"
end

local function plugin_loop()
  -- Printf("tick")
  pluginAlive = true
  if pluginRunning then
    -- Loop goes here
  end
  local refreshrate = tonumber(get_global("ST_RefreshRateValue", "1")) or
      tonumber(get_global("TM_RefreshRateValue", "1")) or 1
  coroutine.yield(refreshrate)
end

local function plugin_kill()
  pluginAlive = false
  signalTable.plugin_off()
  local ov = GetDisplayByIndex(1).ScreenOverlay
  local menu = ov:FindRecursive(UI_MENU_NAME)
  if menu then
    FindBestFocus(menu)
    presskey("Escape")
  end
  local temp = GetPath("temp", false)
  local uixml = temp .. "SpeedtoTime_UI.xml"
  if FileExists(uixml) then
    os.remove(uixml)
    Printf("Removed " .. uixml)
  end
  delete_CMDlineIcon()
end

local function main()
  if not pluginAlive or nil then
    if is_valid_ui_item(UI_CMD_ICON_NAME, "CmdLineSection") then
      pluginAlive = true
    else
      pluginAlive = false
      create_CMDlineIcon()
    end
    Timer(plugin_loop, 0, 0, plugin_kill)
    signalTable.cmdbar_clicked()
    return
  else
    signalTable.cmdbar_clicked()
  end
end

return main
