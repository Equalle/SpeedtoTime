---@diagnostic disable: redundant-parameter
local pluginName = select(1, ...)
local componentName = select(2, ...)
local signalTable = select(3, ...)
local myHandle = select(4, ...)

-- CONSTANTS
local PLUGIN_NAME = 'SpeedtoTime'
local PLUGIN_VERSION = 'ALPHA 0.0.1'
local UI_CMD_ICON_NAME = PLUGIN_NAME .. 'Icon'
local UI_MENU_NAME = PLUGIN_NAME .. ' Menu'

-- PLUGIN STATE
local pluginAlive = true
local pluginRunning = false
local pluginError = nil

-- HELPER FUNCTIONS - Global Variables
local function get_global(varName, default)
  return GetVar(GlobalVars(), varName) or default
end

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
  -- local base = '/Users/juriseiffert/Library/Mobile Documents/com~apple~CloudDocs/Lua Plugins/GMA3/TimeMAtricks'
  local base = 'C:\\Users\\Juri\\iCloudDrive\\Lua Plugins\\GMA3\\TimeMAtricks'
  local dir = base .. "/"
  local filename, content

  if xmlType == "ui" then
    filename = "SpeedtoTime.xml"
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
    -- { "CloseBtn",    "close" },
    { "SettingsBtn", "open_settings" },
    { "PluginOff",   "plugin_off" },
    { "PluginOn",    "plugin_on" },
    { "FadeLess",    "fade_adjust" },
    { "FadeMore",    "fade_adjust" },
    -- { "Close",       "close" },
    { "Apply",       "apply" },
  }
  for _, b in ipairs(buttons) do
    if not add_ui_element(b[1], overlay, "button", { clicked = b[2] }) then
      ErrPrintf("error at %s", b)
    end
  end

  local holds = {
    { "FadeLess", "fade_hold" },
    { "FadeMore", "fade_hold" },
  }
  for _, h in ipairs(holds) do
    if not add_ui_element(h[1], overlay, "hold", { hold = h[2] }) then
      ErrPrintf("error at %s", h)
    end
  end

  local checks = {
    { "TimingMaster",         "master_swap",     1 },
    { "SpeedMaster",          "master_swap",     0 },
    { "Matricks1Button",      "matricks_toggle", 1 },
    { "Matricks2Button",      "matricks_toggle", 0 },
    { "Matricks3Button",      "matricks_toggle", 0 },
    { "MatricksPrefixButton", "matricks_toggle", 0 },
  }
  for _, c in ipairs(checks) do
    if not add_ui_element(c[1], overlay, "checkbox", { clicked = c[2], state = c[3] }) then
      ErrPrintf("error at %s", c)
    end
  end

  local texts = {
    { "MasterValue",    "text" }, -- no default -> keep existing
    { "Matricks1Value", "text" }, { "Matricks1Rate", "text", "0.25" },
    { "Matricks2Value", "text" }, { "Matricks2Rate", "text", "0.5" },
    { "Matricks3Value", "text" }, { "Matricks3Rate", "text", "1" },
    { "MatricksPrefixValue", "text" },
    --{ "RefreshRateValue",    "text", "1.5" },
  }
  for _, t in ipairs(texts) do
    if not add_ui_element(t[1], overlay, "textbox", { content = t[3] }) then
      ErrPrintf("error at %s", t)
    end
  end

  local rates = {
    { "HT",        "rate_mod",          1 },
    { "ResetRate", "reset_overallrate", 1 },
    { "DT",        "rate_mod",          1 },
  }

  for _, r in ipairs(rates) do
    if not add_ui_element(r[1], overlay, "button", { clicked = r[2] }) then
      ErrPrintf("error at %s", r)
    end
  end

  local plugininfo = {
    { "TitleButton", "TimeMatricks",              "object_matricks" },
    { "Version",     "Version " .. PLUGIN_VERSION },
  }

  for _, p in ipairs(plugininfo) do
    local el = overlay:FindRecursive(p[1])
    if el then
      el.Text = p[2] or ""
      if p[3] then
        el.Icon = p[3]
      end
    end
  end

  -- now load saved globals so they override the defaults set above
--   load_state(overlay)
--   save_state()
  coroutine.yield(0.1) -- slight delay to ensure UI is ready
  if overlay:FindRecursive("MasterValue").Content == "" then
    FindBestFocus(overlay:FindRecursive("MasterValue"))
  else
    FindBestFocus(overlay:FindRecursive("Matricks1Value"))
  end


  local less = overlay:FindRecursive("FadeLess")
  less.BackColor = colors.background.fade

  local more = overlay:FindRecursive("FadeMore")
  more.BackColor = colors.background.delay
end

local function create_CMDlineIcon()
  local cmdbar               = GetDisplayByIndex(1).CmdLineSection
  local lastCols             = tonumber(cmdbar:Get("Columns"))
  local cols                 = lastCols + 1
  cmdbar.Columns             = cols
  cmdbar[2][cols].SizePolicy = "Fixed"
  cmdbar[2][cols].Size       = 50

  Icon                       = cmdbar:Append('Button')
  Icon.Name                  = UI_CMD_ICON_NAME
  Icon.Anchors               = { left = cols - 2 }
  Icon.W                     = 49
  Icon.PluginComponent       = myHandle
  Icon.Clicked               = 'cmdbar_clicked'
  Icon.Icon                  = icons.matricks
  Icon.IconColor             = colors.icon.inactive
  Icon.Tooltip               = "SpeedtoTime Plugin"

  Tri                        = cmdbar:FindRecursive("RightTriangle")
  if Tri then
    Tri.Anchors = { left = cols - 1 }
  end
end

local function delete_CMDlineIcon()
  if Icon then
    local iconpos = Icon:Get("No")
    local cmdbar = GetDisplayByIndex(1).CmdLineSection
    cmdbar:Remove(iconpos)
    local lastCols = tonumber(cmdbar:Get("Columns"))
    cmdbar.Columns = lastCols - 1
    Icon = nil

    local tripos = Tri:Get("No")
    if Tri then
      Tri.Anchors = { left = tripos - 3 }
    end
  end
end

local function main()
    if not pluginAlive or nil then
        if is_valid_ui_item(UI_CMD_ICON_NAME, "CmdLineSection") then
            pluginAlive = true
        else
            pluginAlive = false
            create_CMDlineIcon()

        end
    end
end

return main