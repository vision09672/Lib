local LibraryTools = LibraryMain 
local httpService = game:GetService('HttpService')
local workspace = game:GetService('Workspace')
local ts = game:GetService('TeleportService')
local ps = game:GetService('Players')
local rs = game:GetService('RunService')
local stats = game:GetService('Stats')
local VirtualUser = game:GetService("VirtualUser")

local lp = ps.LocalPlayer
local SaveManager = {} 

do
    SaveManager.Folder = 'VanguardHubSettings'
    SaveManager.Ignore = {}
    SaveManager.LoadedConfigs = {}; -- Track loaded configs to prevent double execution
    SaveManager.AutoSaveEnabled = false
    SaveManager.CurrentConfig = nil
    SaveManager._LastSave = 0
    SaveManager._SaveDelay = 0.5
    SaveManager.MenuKeybindIdx = 'MenuKeybind' -- idx of the KeyPicker that toggles the menu

    SaveManager.Parser = {
        Toggle = {
            Save = function(idx, object) 
                return { type = 'Toggle', idx = idx, value = object.Value } 
            end,
            Load = function(idx, data)
                if Toggles[idx] then 
                    Toggles[idx]:SetValue(data.value)
                end
            end,
        },
        Slider = {
            Save = function(idx, object)
                return { type = 'Slider', idx = idx, value = tostring(object.Value) }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    Options[idx]:SetValue(data.value)
                end
            end,
        },
        Dropdown = {
            Save = function(idx, object)
                return { type = 'Dropdown', idx = idx, value = object.Value, mutli = object.Multi }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    -- a theme that was taken out (Galaxy, God War) must not be selected again from an old config
                    if idx == 'ThemeManager_ThemeList' and type(data.value) == 'string' and Options[idx].Values and not table.find(Options[idx].Values, data.value) then
                        return
                    end

                    Options[idx]:SetValue(data.value)
                end
            end,
        },
        ColorPicker = {
            Save = function(idx, object)
                return { type = 'ColorPicker', idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
                end
            end,
        },
        KeyPicker = {
            Save = function(idx, object)
                return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    Options[idx]:SetValue({ data.key, data.mode })
                end
            end,
        },

        Input = {
            Save = function(idx, object)
                return { type = 'Input', idx = idx, text = object.Value }
            end,
            Load = function(idx, data)
                if Options[idx] and type(data.text) == 'string' then
                    Options[idx]:SetValue(data.text)
                end
            end,
        },

        -- segmented selector (value is the selected option name)
        Selector = {
            Save = function(idx, object)
                return { type = 'Selector', idx = idx, value = object.Value }
            end,
            Load = function(idx, data)
                if Options[idx] and type(data.value) == 'string' then
                    Options[idx]:SetValue(data.value)
                end
            end,
        },

        -- multi-select check list: value is a { Name = true } dictionary
        Checklist = {
            Save = function(idx, object)
                return { type = 'Checklist', idx = idx, value = object.Value }
            end,
            Load = function(idx, data)
                if Options[idx] and type(data.value) == 'table' then
                    Options[idx]:SetValue(data.value)
                end
            end,
        },
    }

    function SaveManager:SetIgnoreIndexes(list)
        for _, key in next, list do
            self.Ignore[key] = true
        end
    end

    function SaveManager:SetFolder(folder)
        self.Folder = folder;
        self:BuildFolderTree()
    end

    function SaveManager:Save(name)
        if (not name) then
            return false, 'no config file is selected'
        end

        local fullPath = self.Folder .. '/settings/' .. name .. '.json'

        local data = {
            objects = {}
        }

        for idx, toggle in next, Toggles do
            if self.Ignore[idx] then continue end

            table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
        end

        for idx, option in next, Options do
            if not self.Parser[option.Type] then continue end
            if self.Ignore[idx] then continue end

            table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
        end    

        local success, encoded = pcall(httpService.JSONEncode, httpService, data)
        if not success then
            return false, 'failed to encode data'
        end

        writefile(fullPath, encoded)
        self.CurrentConfig = name
        return true
    end

    function SaveManager:AutoSave()
        if not (self.AutoSaveEnabled and self.CurrentConfig) then return end

        local now = tick()
        if now - self._LastSave < self._SaveDelay then return end

        self._LastSave = now

        local oldIgnore = table.clone(self.Ignore)

        self:IgnoreThemeSettings()
        self:Save(self.CurrentConfig)

        self.Ignore = oldIgnore
    end

    function SaveManager:FindMenuKeybind()
        local kp = Options[self.MenuKeybindIdx]

        if not kp and self.Library and type(self.Library.ToggleKeybind) == 'table' then
            kp = self.Library.ToggleKeybind
        end

        if kp and kp.Type == 'KeyPicker' then
            return kp
        end
    end

    -- Remembers the menu toggle key in its own file, independent of configs / autosave
    function SaveManager:SetupMenuKeybind()
        local kp = self:FindMenuKeybind()
        if not kp or self._MenuKeybindHooked == kp then return end

        -- keep it out of config files so a config can never reset it
        for idx, option in next, Options do
            if option == kp then
                self.Ignore[idx] = true
            end
        end

        local file = self.Folder .. '/settings/menu_keybind.json'

        if isfile(file) then
            local success, data = pcall(httpService.JSONDecode, httpService, readfile(file))
            if success and type(data) == 'table' and type(data.key) == 'string' then
                kp:SetValue({ data.key, data.mode or kp.Mode })
            end
        end

        self._MenuKeybindHooked = kp

        kp:OnChanged(function()
            pcall(writefile, file, httpService:JSONEncode({ key = kp.Value, mode = kp.Mode }))
        end)
    end

    function SaveManager:SetupAutoSave()
        self:SetupMenuKeybind()

        for _, toggle in next, Toggles do
            toggle:OnChanged(function()
                self:AutoSave()
            end)
        end

        for _, option in next, Options do
            if option.OnChanged then
                option:OnChanged(function()
                    self:AutoSave()
                end)
            end
        end
    end

    function SaveManager:Load(name)
        if (not name) then
            return false, 'no config file is selected'
        end
        
        -- Check if config was already loaded to prevent double execution
        if self.LoadedConfigs[name] then
            return true, 'config already loaded'
        end
        
        local file = self.Folder .. '/settings/' .. name .. '.json'
        if not isfile(file) then return false, 'invalid file' end

        local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
        if not success then return false, 'decode error' end

        for _, option in next, decoded.objects do
            if self.Parser[option.type] and not self.Ignore[option.idx] then
                task.spawn(function() self.Parser[option.type].Load(option.idx, option) end) -- task.spawn() so the config loading wont get stuck.
            end
        end

        -- Mark this config as loaded
        self.LoadedConfigs[name] = true;
        self.CurrentConfig = name
        return true
    end

    function SaveManager:DeleteConfig(name)
        if (not name) then
            return false, 'no config file is selected'
        end
        
        local file = self.Folder .. '/settings/' .. name .. '.json'
        if not isfile(file) then return false, 'invalid file' end
        
        -- Check if this is the autoload config
        if isfile(self.Folder .. '/settings/autoload.txt') then
            local autoload = readfile(self.Folder .. '/settings/autoload.txt')
            if autoload == name then
                -- Delete the autoload file if we're deleting the autoload config
                delfile(self.Folder .. '/settings/autoload.txt')
                if self.AutoloadLabel then
                    self.AutoloadLabel:SetText('Current autoload config: none')
                end
            end
        end
        
        -- Delete the config file
        delfile(file)
        
        -- Remove from loaded configs tracking
        self.LoadedConfigs[name] = nil;
        
        return true
    end
    
    function SaveManager:RemoveAutoload()
        if isfile(self.Folder .. '/settings/autoload.txt') then
            delfile(self.Folder .. '/settings/autoload.txt')
            if self.AutoloadLabel then
                self.AutoloadLabel:SetText('Current autoload config: none')
            end
            return true
        end
        return false, 'no autoload config set'
    end

    function SaveManager:IgnoreThemeSettings()
        self:SetIgnoreIndexes({ 
            "BackgroundColor", "MainColor", "AccentColor", "OutlineColor", "FontColor", -- themes
            "ThemeManager_ThemeList", 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName', 'ThemeManager_HoverPreview', -- themes
            -- the scene follows the theme, the mode / preset are one-shot shortcuts that would overwrite the individual
            -- toggles on load
            'FX_Scene', 'FX_Mode', 'FX_Preset',
        })
    end

    function SaveManager:BuildFolderTree()
        local paths = {
            self.Folder,
            self.Folder .. '/themes',
            self.Folder .. '/settings'
        }

        for i = 1, #paths do
            local str = paths[i]
            if not isfolder(str) then
                makefolder(str)
            end
        end
    end

    function SaveManager:RefreshConfigList()
        local list = listfiles(self.Folder .. '/settings')

        local out = {}
        for i = 1, #list do
            local file = list[i]
            if file:sub(-5) == '.json' then
                -- i hate this but it has to be done ...

                local pos = file:find('.json', 1, true)
                local start = pos

                local char = file:sub(pos, pos)
                while char ~= '/' and char ~= '\\' and char ~= '' do
                    pos = pos - 1
                    char = file:sub(pos, pos)
                end

                if char == '/' or char == '\\' then
                    table.insert(out, file:sub(pos + 1, start - 1))
                end
            end
        end
        
        return out
    end

    function SaveManager:SetLibrary(library)
        self.Library = library
    end

    function SaveManager:LoadAutoloadConfig()
        self:SetupMenuKeybind()

        if isfile(self.Folder .. '/settings/autoload.txt') then
            local name = readfile(self.Folder .. '/settings/autoload.txt')

            local success, err = self:Load(name)
            if not success then
                return self.Library:Notify('Failed to load autoload config: ' .. err)
            end

            self.Library:Notify(string.format('Auto loaded config %q', name))
        end

        if not self.CurrentConfig then
            self.CurrentConfig = "autosave"
            self:Save("autosave")
        end
    end

    function SaveManager:BuildConfigSection(tab)
        assert(self.Library, 'Must set SaveManager.Library')

        -- small helper: category heading (falls back to a divider if an older Library without AddSection is loaded)
        local function Section(box, text)
            if box.AddSection then
                box:AddSection(text)
            else
                box:AddDivider()
            end
        end

        local misc = tab:AddLeftGroupbox('General') -- under the Menu groupbox on the left; Configuration stays on the right

        Section(misc, 'Saving')

        misc:AddToggle('AutoSave misc', {
            Text = 'Auto Save',
            Default = false,
            Tooltip = 'Saves your settings automatically every time you change something',
            Callback = function(Value)
                SaveManager.AutoSaveEnabled = Value
                if Value then
                    if not SaveManager.CurrentConfig then
                        SaveManager.CurrentConfig = "autosave"
                    end

                    SaveManager:Save(SaveManager.CurrentConfig)
                    writefile(SaveManager.Folder .. '/settings/autoload.txt', SaveManager.CurrentConfig)
                else
                    if isfile(SaveManager.Folder .. '/settings/autoload.txt') then
                        delfile(SaveManager.Folder .. '/settings/autoload.txt')
                    end

                    local file = SaveManager.Folder .. '/settings/autosave.json'
                    if isfile(file) then
                        delfile(file)
                    end

                    SaveManager.CurrentConfig = nil
                end
            end
        })

        Section(misc, 'Safety')

        misc:AddToggle('AntiAFK misc', {
            Text = 'Anti AFK',
            Default = false,
            Tooltip = 'Stops Roblox from kicking you for being idle'
        })

        Section(misc, 'Performance')

        misc:AddToggle('Performance misc', {
            Text = 'Disable 3D Rendering',
            Default = false,
            Tooltip = 'Stops drawing the 3D world to save GPU. The menu stays visible',
            Callback = function(Value)
                rs:Set3dRenderingEnabled(not Value)
            end
        })

        misc:AddToggle('FPSLock misc', {
            Text = 'Lock FPS to 30',
            Default = false,
            Tooltip = 'Caps the frame rate at 30 (needs an executor with setfpscap)',
            Callback = function(Value)
                if setfpscap then
                    setfpscap(Value and 30 or 0)
                end
            end
        })

        Section(misc, 'HUD')

        misc:AddToggle('Watermark misc', {
            Text = 'Watermark',
            Default = false,
            Tooltip = 'Small bar with game, FPS and ping',
            Callback = function(Value)
                LibraryTools:SetWatermarkVisibility(Value)
            end
        })

        misc:AddToggle('Keybinds misc', {
            Text = 'Keybind List',
            Default = false,
            Tooltip = 'Panel that lists your keybinds',
            Callback = function(Value)
                LibraryTools.KeybindFrame.Visible = Value
            end
        })

        Section(misc, 'Session')

        misc:AddButton({
            Text = 'Rejoin',
            Func = function()
                ts:Teleport(game.PlaceId, lp)
            end,
            DoubleClick = true
        })
        :AddButton({
            Text = 'Leave',
            Func = function()
                game:Shutdown()
            end,
            DoubleClick = true
        })
        local section = tab:AddRightGroupbox('Configuration')

        Section(section, 'Select')

        section:AddInput('SaveManager_ConfigName',    { Text = 'Config name' })
        section:AddDropdown('SaveManager_ConfigList', { Text = 'Config list', Values = self:RefreshConfigList(), AllowNull = true })

        Section(section, 'Manage')

        section:AddButton('Create config', function()
            local name = Options.SaveManager_ConfigName.Value

            if name:gsub(' ', '') == '' then 
                return self.Library:Notify('Invalid config name (empty)', 2)
            end

            local success, err = self:Save(name)
            if not success then
                return self.Library:Notify('Failed to save config: ' .. err)
            end

            self.Library:Notify(string.format('Created config %q', name))

            Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Options.SaveManager_ConfigList:SetValue(nil)
        end):AddButton('Load config', function()
            local name = Options.SaveManager_ConfigList.Value

            local success, err = self:Load(name)
            if not success then
                return self.Library:Notify('Failed to load config: ' .. err)
            end

            self.Library:Notify(string.format('Loaded config %q', name))
        end)

        section:AddButton('Overwrite config', function()
            local name = Options.SaveManager_ConfigList.Value

            local success, err = self:Save(name)
            if not success then
                return self.Library:Notify('Failed to overwrite config: ' .. err)
            end

            self.Library:Notify(string.format('Overwrote config %q', name))
        end)
        
        section:AddButton('Delete config', function()
            local name = Options.SaveManager_ConfigList.Value
            
            if not name then
                return self.Library:Notify('No config selected', 2)
            end
            
            local success, err = self:DeleteConfig(name)
            if not success then
                return self.Library:Notify('Failed to delete config: ' .. err)
            end
            
            self.Library:Notify(string.format('Deleted config %q', name))
            
            Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Options.SaveManager_ConfigList:SetValue(nil)
        end)

        section:AddButton('Refresh list', function()
            Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Options.SaveManager_ConfigList:SetValue(nil)
        end)

        Section(section, 'Autoload')

        section:AddButton('Set as autoload', function()
            local name = Options.SaveManager_ConfigList.Value
            
            if not name then
                return self.Library:Notify('No config selected', 2)
            end
            
            writefile(self.Folder .. '/settings/autoload.txt', name)
            SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
            self.Library:Notify(string.format('Set %q to auto load', name))
        end):AddButton('Remove autoload', function()
            local success, err = self:RemoveAutoload()
            if not success then
                return self.Library:Notify('Failed to remove autoload: ' .. err)
            end
            
            self.Library:Notify('Removed autoload config')
        end)

        SaveManager.AutoloadLabel = section:AddLabel('Current autoload config: none', true)

        if isfile(self.Folder .. '/settings/autoload.txt') then
            local name = readfile(self.Folder .. '/settings/autoload.txt')
            SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
        end

        SaveManager:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName' })
        SaveManager:SetupMenuKeybind()
    end

    SaveManager:BuildFolderTree()
end

-- Library functions
-- Sets the watermark visibility
-- LibraryTools:SetWatermarkVisibility(true)

-- Example of dynamically-updating watermark with common traits (fps and ping)
local FrameTimer = tick()
local FrameCounter = 0;
local FPS = 60;

-- GetProductInfo is a web request: fetch the game name once instead of every frame
local GameName = 'Unknown'
task.spawn(function()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    if ok and info then
        GameName = tostring(info.Name)
    end
end)

local ExecutorName = tostring(identifyexecutor and identifyexecutor() or 'Unknown')

local WatermarkConnection = rs.RenderStepped:Connect(function()
    FrameCounter += 1;

    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter;
        FrameTimer = tick();
        FrameCounter = 0;
    end;

    local timeTable = os.date("*t")
    LibraryTools:SetWatermark(('Vanguard Hub | ' .. GameName .. ' | ' .. ExecutorName .. ' | ' .. tostring(timeTable.day .. "/" .. timeTable.month .. "/" .. timeTable.year) .. ' | %s fps | %s ms'):format(
        math.floor(FPS),
        math.floor(stats.Network.ServerStatsItem['Data Ping']:GetValue())
    ));
end);

lp.Idled:Connect(function()
    if Toggles['AntiAFK misc'].Value then
        VirtualUser:Button2Down(Vector2.new(), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(), workspace.CurrentCamera.CFrame)
    end
end)

LibraryTools:OnUnload(function()
    for key, value in pairs(Toggles) do 
        if key ~= 'AutoSave misc' then
            value:SetValue(false)
        end
    end
    task.wait(1)
    LibraryTools:SetWatermarkVisibility(false)
    WatermarkConnection:Disconnect()
    LibraryTools.KeybindFrame.Visible = false
    task.wait()
    LibraryTools.Unloaded = true
end)

return SaveManager
