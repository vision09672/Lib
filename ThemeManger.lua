local cloneref = cloneref or function(o) return o end
local httpService = cloneref(game:GetService('HttpService'))
local httprequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
local getassetfunc = getcustomasset or getsynasset
local ThemeManager = {} 
do
	ThemeManager.Folder = 'VanguardHubTheme'
	if not isfolder(ThemeManager.Folder) then makefolder(ThemeManager.Folder) end
	ThemeManager.Library = nil
	ThemeManager.BuiltInThemes = {
		['Default'] 	= { 1, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"232330","AccentColor":"426e87","BackgroundColor":"1d1b26","OutlineColor":"27232f"}') },
		['Tokyo'] 		= { 2, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor":"6759b3","BackgroundColor":"16161f","OutlineColor":"323232"}') },
		['Purple'] 		= { 4, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1e1e","AccentColor":"7e48a3","BackgroundColor":"232323","OutlineColor":"141414"}') },
		['Jester'] 		= { 5, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"db4467","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Mint'] 		= { 6, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"3db488","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Orange'] 		= { 7, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1e1e","AccentColor":"ff4c00","BackgroundColor":"232323","OutlineColor":"141414"}') },
		['Dracula'] 	= { 24, httpService:JSONDecode('{"FontColor":"f8f8f2","MainColor":"282a36","AccentColor":"bd93f9","BackgroundColor":"1e1f29","OutlineColor":"44475a"}') },
		['Steel'] 		= { 28, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"2b2f33","AccentColor":"7289da","BackgroundColor":"23272a","OutlineColor":"1e2124"}') },
		['Blue Core'] 	= { 30, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"2b2b2b","AccentColor":"0094ff","BackgroundColor":"1e1e1e","OutlineColor":"3a3a3a"}') },

		-- themes below come with an animated scene (see ThemeMeta); the ones above stay clean on purpose
		['Vanguard'] 	= { 39, httpService:JSONDecode('{"FontColor":"ffe9e9","MainColor":"1d0d10","AccentColor":"ff2a3d","BackgroundColor":"120609","OutlineColor":"4a1620"}') },
		['Void'] 		= { 40, httpService:JSONDecode('{"FontColor":"d8d8e8","MainColor":"101018","AccentColor":"8b7cff","BackgroundColor":"08080d","OutlineColor":"232333"}') },
		['Ocean'] 		= { 42, httpService:JSONDecode('{"FontColor":"e8f6ff","MainColor":"0f2a3d","AccentColor":"2fb8d6","BackgroundColor":"0a1d2c","OutlineColor":"1c4a63"}') },
		['Sakura'] 		= { 43, httpService:JSONDecode('{"FontColor":"fff0f5","MainColor":"2a1822","AccentColor":"ff8fb8","BackgroundColor":"1c0f17","OutlineColor":"4f2d41"}') },
		['Heaven'] 		= { 45, httpService:JSONDecode('{"FontColor":"f4f1ff","MainColor":"16245a","AccentColor":"ffd98a","BackgroundColor":"0e1a46","OutlineColor":"3a4375"}') },
		['Cyber'] 		= { 46, httpService:JSONDecode('{"FontColor":"e6fbff","MainColor":"0d1424","AccentColor":"00e5ff","BackgroundColor":"070b16","OutlineColor":"1c3350"}') },
		['Inferno'] 	= { 47, httpService:JSONDecode('{"FontColor":"fff1e6","MainColor":"261210","AccentColor":"ff6a1f","BackgroundColor":"170a08","OutlineColor":"4a2118"}') },
		['Deep Sea'] 	= { 48, httpService:JSONDecode('{"FontColor":"dff6ff","MainColor":"06192b","AccentColor":"00e0c6","BackgroundColor":"030a14","OutlineColor":"0e3550"}') },
	}

	-- themes that were taken out: a saved theme with one of these names (a config, default.txt, a custom theme) falls back instead of breaking
	ThemeManager.RemovedThemes = { ['Galaxy'] = true, ['God War'] = true }

	-- Scene = animated scene from Library.FX.Scenes that goes with the colors. Weight = Clean / Balanced / Beautiful / Extreme.
	-- Themes not listed here are plain color themes with no scene.
	ThemeManager.ThemeMeta = {
		['Vanguard'] 	= { Scene = 'Vanguard', Weight = 'Extreme' };
		['Void'] 		= { Scene = 'Void', Weight = 'Balanced' };
		['Ocean'] 		= { Scene = 'Ocean', Weight = 'Balanced' };
		['Sakura'] 		= { Scene = 'Sakura', Weight = 'Beautiful' };
		['Heaven'] 		= { Scene = 'Heaven', Weight = 'Beautiful' };
		['Cyber'] 		= { Scene = 'Cyber', Weight = 'Extreme' };
		['Inferno'] 	= { Scene = 'Inferno', Weight = 'Extreme' };
		['Deep Sea'] 	= { Scene = 'Deep Sea', Weight = 'Beautiful' };
	}

	ThemeManager.VisualModes = {
		Minimal  = { Performance = 'Minimal';   Background = false; Particles = false; Decorations = false; Animations = false; Transitions = false; Ambient = false; };
		Normal   = { Performance = 'Balanced';  Intensity = 'Medium'; Background = true; Particles = true; Decorations = true; Animations = true; Transitions = true; Ambient = true; };
		Showcase = { Performance = 'Beautiful'; Intensity = 'High';   Background = true; Particles = true; Decorations = true; Animations = true; Transitions = true; Ambient = true; };
	}

	-- subtitle shown under each card in the theme grid
	ThemeManager.ThemeDescriptions = {
		['Default'] 	= 'Slate · Steel blue',
		['Tokyo'] 		= 'Night · Indigo',
		['Purple'] 		= 'Charcoal · Violet',
		['Jester'] 		= 'Graphite · Rose',
		['Mint'] 		= 'Graphite · Mint',
		['Orange'] 		= 'Charcoal · Ember',
		['Dracula'] 	= 'Midnight · Lavender',
		['Steel'] 		= 'Gunmetal · Blurple',
		['Blue Core'] 	= 'Carbon · Azure',
		['Vanguard'] 	= 'Crimson · Steel red',
		['Void'] 		= 'Near-black · Violet',
		['Ocean'] 		= 'Navy · Aqua',
		['Sakura'] 		= 'Plum · Blossom',
		['Heaven'] 		= 'Indigo · Halo gold',
		['Cyber'] 		= 'Night · Neon cyan',
		['Inferno'] 	= 'Ember · Lava',
		['Deep Sea'] 	= 'Abyss · Bioluminescent',
	}

	-- Live preview: paint the whole UI with a theme while hovering its card, without touching the color pickers
	function ThemeManager:PreviewTheme(theme)
		local data = self.BuiltInThemes[theme]
		if not data then return end

		local lib = self.Library
		for idx, col in next, data[2] do
			lib[idx] = Color3.fromHex(col)
		end

		lib.AccentColorDark = lib:GetDarkerColor(lib.AccentColor)
		lib.SelectedColor = lib.BackgroundColor:Lerp(lib.AccentColor, 0.14)
		lib.DimFontColor = lib.FontColor:Lerp(lib.BackgroundColor, 0.45)
		lib:UpdateColorsUsingRegistry()
	end

	-- Go back to whatever the color pickers hold (the applied theme)
	function ThemeManager:EndPreview()
		self:ThemeUpdate()
	end

	function ApplyBackgroundVideo(webmLink)
		if writefile == nil then return end;if readfile == nil then return end;if isfile == nil then return end
		if ThemeManager.Library == nil then return end
		if ThemeManager.Library.InnerVideoBackground == nil then return end

		if string.sub(tostring(webmLink), -5) == ".webm" then
			local CurrentSaved = ""
			if isfile(ThemeManager.Folder .. '/themes/currentVideoLink.txt') then
				CurrentSaved = readfile(ThemeManager.Folder .. '/themes/currentVideoLink.txt')
			end
			local VideoData = nil;
			if CurrentSaved == tostring(webmLink) then
				VideoData = {
					Success = true,
					Body = nil
				}
			else
				VideoData = httprequest({
					Url = tostring(webmLink),
					Method = 'GET'
				})
			end
			
			if (VideoData.Success) then
				VideoData = VideoData.Body
				if (isfile(ThemeManager.Folder .. '/themes/currentVideo.webm') == false and VideoData ~= nil) or VideoData ~= nil then
					writefile(ThemeManager.Folder .. '/themes/currentVideo.webm', VideoData)
					writefile(ThemeManager.Folder .. '/themes/currentVideoLink.txt', tostring(webmLink))
				end
				
				local Video = getassetfunc(ThemeManager.Folder .. '/themes/currentVideo.webm')
				ThemeManager.Library.InnerVideoBackground.Video = Video
				ThemeManager.Library.InnerVideoBackground.Visible = true
				ThemeManager.Library.InnerVideoBackground:Play()
			end
		end
	end
	
	function ThemeManager:ApplyTheme(theme)
		if self.RemovedThemes[theme] then
			theme = self.BuiltInThemes['Vanguard'] and 'Vanguard' or 'Default'
		end

		local customThemeData = self:GetCustomTheme(theme)
		local data = customThemeData or self.BuiltInThemes[theme]

		if not data then return end

		-- custom themes are just regular dictionaries instead of an array with { index, dictionary }
		if self.Library.InnerVideoBackground ~= nil then
			self.Library.InnerVideoBackground.Visible = false
		end

		local scheme = customThemeData or data[2]

		-- animated scene that goes with this theme (custom themes store theirs under "Scene")
		local meta = self.ThemeMeta[theme]
		local sceneName = (customThemeData and customThemeData.Scene) or (meta and meta.Scene)
		if self.RemovedThemes[sceneName] then
			sceneName = nil
		end


		-- while Applying is true the color pickers' OnChanged won't re-run ThemeUpdate for every single color
		self.Applying = true
		local ok, err = pcall(function()
			for idx, col in next, scheme do
				if idx == "Scene" then
					-- applied after the colors
				elseif idx ~= "VideoLink" then
					self.Library[idx] = Color3.fromHex(col)

					if getgenv().Linoria.Options[idx] then
						getgenv().Linoria.Options[idx]:SetValueRGB(Color3.fromHex(col))
					end
				else
					self.Library[idx] = col

					if getgenv().Linoria.Options[idx] then
						getgenv().Linoria.Options[idx]:SetValue(col)
					end

					ApplyBackgroundVideo(col)
				end
			end
		end)
		self.Applying = false

		if not ok then warn('ThemeManager: failed to apply theme:', err) end

		self:ThemeUpdate()

		-- themes without a scene go back to the clean look
		if self.Library.FX then
			self.Library.FX:SetScene(sceneName)
		end
	end

	function ThemeManager:ThemeUpdate()
		-- This allows us to force apply themes without loading the themes tab :)
		if self.Library.InnerVideoBackground ~= nil then
			self.Library.InnerVideoBackground.Visible = false
		end
		
		local options = { "FontColor", "MainColor", "AccentColor", "BackgroundColor", "OutlineColor", "VideoLink" }
		for i, field in next, options do
			if getgenv().Linoria.Options and getgenv().Linoria.Options[field] then
				self.Library[field] = getgenv().Linoria.Options[field].Value
				if field == "VideoLink" then
					ApplyBackgroundVideo(getgenv().Linoria.Options[field].Value)
				end
			end
		end

		local lib = self.Library
		lib.AccentColorDark = lib:GetDarkerColor(lib.AccentColor);
		-- derived colors used by the sidebar (selected tab / dim text)
		lib.SelectedColor = lib.BackgroundColor:Lerp(lib.AccentColor, 0.14)
		lib.DimFontColor = lib.FontColor:Lerp(lib.BackgroundColor, 0.45)
		lib:UpdateColorsUsingRegistry()
	end

	function ThemeManager:LoadDefault()		
		local theme = self.BuiltInThemes['Vanguard'] and 'Vanguard' or 'Default'
		local content = isfile(self.Folder .. '/themes/default.txt') and readfile(self.Folder .. '/themes/default.txt')

		local isDefault = true
		if content then
			if self.BuiltInThemes[content] then
				theme = content
			elseif self:GetCustomTheme(content) then
				theme = content
				isDefault = false;
			end
		elseif self.BuiltInThemes[self.DefaultTheme] then
		theme = self.DefaultTheme
		end

		if isDefault then
			getgenv().Linoria.Options.ThemeManager_ThemeList:SetValue(theme)
		else
			self:ApplyTheme(theme)
		end
	end

	function ThemeManager:SaveDefault(theme)
		writefile(self.Folder .. '/themes/default.txt', theme)
	end

	function ThemeManager:Delete(name)
		if (not name) then
			return false, 'no config file is selected'
		end
		
		local file = self.Folder .. '/themes/' .. name .. '.json'
		if not isfile(file) then return false, 'invalid file' end

		local success, decoded = pcall(delfile, file)
		if not success then return false, 'delete file error' end
		
		return true
	end
	

	function ThemeManager:CreateThemeManager(groupbox)
		-- category heading (falls back to a divider if an older Library without AddSection is loaded)
		local function Section(text)
			if groupbox.AddSection then
				groupbox:AddSection(text)
			else
				groupbox:AddDivider()
			end
		end

		local ThemesArray = {}
		for Name, Theme in next, self.BuiltInThemes do
			table.insert(ThemesArray, Name)
		end

		table.sort(ThemesArray, function(a, b) return self.BuiltInThemes[a][1] < self.BuiltInThemes[b][1] end)

		local ThemeCards = {}
		for _, Name in ipairs(ThemesArray) do
			local scheme = self.BuiltInThemes[Name][2]
			local meta = self.ThemeMeta[Name]
			local sceneDef = meta and self.Library.FX and self.Library.FX.Scenes[meta.Scene]
			table.insert(ThemeCards, {
				Name = Name,
				Subtitle = self.ThemeDescriptions[Name] or ('#' .. tostring(scheme.AccentColor)),
				Animated = sceneDef ~= nil,
				Scene = sceneDef and sceneDef.Name or nil,
				Colors = {
					BackgroundColor = Color3.fromHex(scheme.BackgroundColor),
					MainColor = Color3.fromHex(scheme.MainColor),
					AccentColor = Color3.fromHex(scheme.AccentColor),
					OutlineColor = Color3.fromHex(scheme.OutlineColor),
					FontColor = Color3.fromHex(scheme.FontColor),
				},
			})
		end

		-- ===== Presets: pick a ready-made theme =====
		Section('Presets')

		groupbox:AddToggle('ThemeManager_HoverPreview', { Text = 'Live preview on hover', Default = false, Tooltip = 'Hover a card to preview its colors on the whole menu' })

		local Previewing = false
		groupbox:AddThemeGrid('ThemeManager_ThemeList', {
			Themes = ThemeCards,
			Default = self.BuiltInThemes['Vanguard'] and 'Vanguard' or ThemesArray[1],
			OnHover = function(Name)
				if not getgenv().Linoria.Toggles.ThemeManager_HoverPreview.Value then return end
				Previewing = true
				self:PreviewTheme(Name)
			end,
			OnHoverEnd = function()
				if not Previewing then return end
				Previewing = false
				self:EndPreview()
			end,
		})
		groupbox:AddButton({ Text = 'Set as default', Tooltip = 'Load the selected preset every time the script starts', Func = function()
			self:SaveDefault(getgenv().Linoria.Options.ThemeManager_ThemeList.Value)
			self.Library:Notify(string.format('Set default theme to %q', getgenv().Linoria.Options.ThemeManager_ThemeList.Value))
		end })

		getgenv().Linoria.Options.ThemeManager_ThemeList:OnChanged(function()
			Previewing = false
			self:ApplyTheme(getgenv().Linoria.Options.ThemeManager_ThemeList.Value)
		end)

		-- ===== Colors: fine-tune the five theme colors =====
		Section('Colors')

		groupbox:AddLabel('Background color'):AddColorPicker('BackgroundColor', { Default = self.Library.BackgroundColor });
		groupbox:AddLabel('Main color')	:AddColorPicker('MainColor', { Default = self.Library.MainColor });
		groupbox:AddLabel('Accent color'):AddColorPicker('AccentColor', { Default = self.Library.AccentColor });
		groupbox:AddLabel('Outline color'):AddColorPicker('OutlineColor', { Default = self.Library.OutlineColor });
		groupbox:AddLabel('Font color')	:AddColorPicker('FontColor', { Default = self.Library.FontColor });

		-- ===== Custom themes: save your own colors =====
		Section('Custom themes')

		groupbox:AddInput('ThemeManager_CustomThemeName', { Text = 'Theme name' })
		groupbox:AddButton('Create theme', function()
			self:SaveCustomTheme(getgenv().Linoria.Options.ThemeManager_CustomThemeName.Value)

			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValue(nil)
		end)

		groupbox:AddDropdown('ThemeManager_CustomThemeList', { Text = 'Saved themes', Values = self:ReloadCustomThemes(), AllowNull = true, Default = 1 })

		groupbox:AddButton('Load theme', function()
			self:ApplyTheme(getgenv().Linoria.Options.ThemeManager_CustomThemeList.Value)
		end):AddButton('Overwrite theme', function()
			self:SaveCustomTheme(getgenv().Linoria.Options.ThemeManager_CustomThemeName.Value)
		end)

		groupbox:AddButton('Delete theme', function()
			local name = getgenv().Linoria.Options.ThemeManager_CustomThemeName.Value

			local success, err = self:Delete(name)
			if not success then
				return self.Library:Notify('Failed to delete theme: ' .. err)
			end

			self.Library:Notify(string.format('Deleted theme %q', name))
			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValue(nil)
		end):AddButton('Refresh list', function()
			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValue(nil)
		end)

		groupbox:AddButton('Set as default', function()
			if getgenv().Linoria.Options.ThemeManager_CustomThemeList.Value ~= nil and getgenv().Linoria.Options.ThemeManager_CustomThemeList.Value ~= '' then
				self:SaveDefault(getgenv().Linoria.Options.ThemeManager_CustomThemeList.Value)
				self.Library:Notify(string.format('Set default theme to %q', getgenv().Linoria.Options.ThemeManager_CustomThemeList.Value))
			end
		end):AddButton('Reset default', function()
			local success = pcall(delfile, self.Folder .. '/themes/default.txt')
			if not success then
				return self.Library:Notify('Failed to reset default: delete file error')
			end

			self.Library:Notify('Set default theme to nothing')
			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			getgenv().Linoria.Options.ThemeManager_CustomThemeList:SetValue(nil)
		end)

		ThemeManager:LoadDefault()

		local function UpdateTheme()
			if self.Applying then return end
			self:ThemeUpdate()
		end

		getgenv().Linoria.Options.BackgroundColor:OnChanged(UpdateTheme)
		getgenv().Linoria.Options.MainColor:OnChanged(UpdateTheme)
		getgenv().Linoria.Options.AccentColor:OnChanged(UpdateTheme)
		getgenv().Linoria.Options.OutlineColor:OnChanged(UpdateTheme)
		getgenv().Linoria.Options.FontColor:OnChanged(UpdateTheme)
	end
	function ThemeManager:GetCustomTheme(file)
		local path = self.Folder .. '/themes/' .. file
		if not isfile(path) then
			return nil
		end

		local data = readfile(path)
		local success, decoded = pcall(httpService.JSONDecode, httpService, data)
		
		if not success then
			return nil
		end

		return decoded
	end

	function ThemeManager:SaveCustomTheme(file)
		if file:gsub(' ', '') == '' then
			return self.Library:Notify('Invalid file name for theme (empty)', 3)
		end

		local theme = {}
		local fields = { "FontColor", "MainColor", "AccentColor", "BackgroundColor", "OutlineColor", "VideoLink" }

		for _, field in next, fields do
			local option = getgenv().Linoria.Options[field]

			if option and option.Value then
				if field == "VideoLink" then
					theme[field] = option.Value
				else
					theme[field] = option.Value.ToHex and option.Value:ToHex() or option.Value
				end
			else
				warn("Missing theme field:", field)
			end
		end

		-- keep the active animated scene with the colors
		local fx = self.Library.FX
		if fx and fx.SceneName ~= 'None' then
			theme.Scene = fx.SceneName
		end

		writefile(self.Folder .. '/themes/' .. file .. '.json', httpService:JSONEncode(theme))
	end

	function ThemeManager:ReloadCustomThemes()
		local list = listfiles(self.Folder .. '/themes')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == '.json' then
				-- i hate this but it has to be done ...

				local pos = file:find('.json', 1, true)
				local char = file:sub(pos, pos)

				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1))
				end
			end
		end

		return out
	end

	function ThemeManager:SetLibrary(lib)
		self.Library = lib
	end

	function ThemeManager:BuildFolderTree()
		local paths = {}

		-- build the entire tree if a path is like some-hub/phantom-forces
		-- makefolder builds the entire tree on Synapse X but not other exploits

		local parts = self.Folder:split('/')
		for idx = 1, #parts do
			paths[#paths + 1] = table.concat(parts, '/', 1, idx)
		end

		table.insert(paths, self.Folder .. '/themes')

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function ThemeManager:SetFolder(folder)
		self.Folder = folder
		self:BuildFolderTree()
	end

	-- Applies one of ThemeManager.VisualModes (Minimal / Normal / Showcase) and syncs the controls without re-triggering them.
	function ThemeManager:ApplyVisualMode(mode)
		local cfg = self.VisualModes[mode]
		if not cfg then return end

		local lib = self.Library
		local fx = lib.FX
		local Opts, Tgls = getgenv().Linoria.Options, getgenv().Linoria.Toggles

		fx._syncing = true
		fx:Configure(cfg)

		for id, key in next, {
			FX_Background = 'Background', FX_Particles = 'Particles', FX_Decorations = 'Decorations',
			FX_Animations = 'Animations', FX_Transitions = 'Transitions', FX_Ambient = 'Ambient',
		} do
			if Tgls[id] then Tgls[id]:SetValue(cfg[key]) end
		end

		if Opts.FX_Intensity then Opts.FX_Intensity:SetValue(fx.Settings.Intensity) end
		if Opts.FX_Performance then Opts.FX_Performance:SetValue(fx.Settings.Performance) end
		fx._syncing = false

		-- Minimal is the "clean UI" shortcut, so the UI-only looks go off too (these controls act on their own)
		if mode == 'Minimal' then
			for _, id in ipairs({ 'Lab_Glow', 'Lab_RGB', 'Lab_Cinematic' }) do
				if Tgls[id] then Tgls[id]:SetValue(false) end
			end
		end
	end

	-- All visual-engine controls, added next to the color themes (called by ApplyToTab).
	function ThemeManager:CreateVisualUI(tab)
		local lib = self.Library
		local fx = lib.FX
		local Opts, Tgls = getgenv().Linoria.Options, getgenv().Linoria.Toggles

		-- controls call this; while the mode buttons sync the toggles it is muted
		local function Cfg(tbl)
			if fx._syncing then return end
			fx:Configure(tbl)
		end

		-- category heading (falls back to a divider if an older Library without AddSection is loaded)
		local function Section(box, text)
			if box.AddSection then
				box:AddSection(text)
			else
				box:AddDivider()
			end
		end

		-- ================= Visual Settings =================
		local Visual = tab:AddRightGroupbox('Visual Settings')

		Section(Visual, 'Mode')

		Visual:AddSelector('FX_Mode', {
			Text = 'Visual mode', Values = { 'Minimal', 'Normal', 'Showcase' }, Default = 'Normal',
			Callback = function(v)
				if fx._syncing then return end
				self:ApplyVisualMode(v)
			end,
		})

		Visual:AddButton({
			Text = 'Clean mode',
			Tooltip = 'Turn every effect off at once',
			Func = function()
				self:ApplyVisualMode('Minimal')
				fx._syncing = true
				Opts.FX_Mode:SetValue('Minimal')
				fx._syncing = false
			end,
		})

		Section(Visual, 'Layers')

		Visual:AddToggle('FX_Background', { Text = 'Animated Background', Default = true, Tooltip = 'Theme scene behind the window', Callback = function(v) Cfg({ Background = v }) end })
		Visual:AddToggle('FX_Particles', { Text = 'Particles', Default = true, Tooltip = 'Bubbles, petals, embers, digital rain...', Callback = function(v) Cfg({ Particles = v }) end })
		Visual:AddToggle('FX_Decorations', { Text = 'Decorations', Default = true, Tooltip = 'Theme objects around the window: flowers, coral, swords, the scale and the crucifix, kraken arms...', Callback = function(v) Cfg({ Decorations = v }) end })
		Visual:AddToggle('FX_Animations', { Text = 'Theme Animations', Default = true, Tooltip = 'Off = the scene is drawn but nothing moves', Callback = function(v) Cfg({ Animations = v }) end })
		Visual:AddToggle('FX_Transitions', { Text = 'Tab Transitions', Default = true, Tooltip = 'Short theme animation when you change tab', Callback = function(v) Cfg({ Transitions = v }) end })
		Visual:AddToggle('FX_Ambient', { Text = 'Ambient Effects', Default = true, Tooltip = 'Glows, light sweeps and scan lines', Callback = function(v) Cfg({ Ambient = v }) end })

		Section(Visual, 'Quality')

		Visual:AddDropdown('FX_Intensity', {
			Text = 'Intensity', Values = { 'Off', 'Low', 'Medium', 'High', 'Extreme' }, Default = 'Medium',
			Tooltip = 'How many particles a scene may use',
			Callback = function(v) Cfg({ Intensity = v }) end,
		})

		Visual:AddSelector('FX_Performance', {
			Text = 'Performance', Values = { 'Minimal', 'Balanced', 'Beautiful', 'Extreme' }, Default = 'Balanced',
			Callback = function(v) Cfg({ Performance = v }) end,
		})

		Section(Visual, 'Privacy')

		Visual:AddToggle('FX_ShowName', {
			Text = 'Show Username', Default = true,
			Tooltip = 'Hides your name, @handle and avatar everywhere in this UI',
			Callback = function(v) lib:SetShowName(v) end,
		})

		-- ================= Theme Engine =================
		local Engine = tab:AddRightGroupbox('Theme Engine')

		Section(Engine, 'Scene')

		local sceneValues = { 'None' }
		for _, name in ipairs(fx.SceneOrder) do
			table.insert(sceneValues, name)
		end

		Engine:AddDropdown('FX_Scene', {
			Text = 'Scene', Values = sceneValues, Default = 'None',
			Tooltip = 'Pick an animated scene on its own, with any color theme',
			Callback = function(v)
				if fx._syncing or not lib.Window then return end

				if not lib.Window:SetScene(v ~= 'None' and v or nil) then
					fx._syncing = true
					Opts.FX_Scene:SetValue(fx.SceneName)
					fx._syncing = false
				end
			end,
		})

		local SceneStatus = Engine:AddLabel('No scene - clean UI')

		-- keep the dropdown and the status line in step with whatever theme / preset picked the scene
		local function SceneChanged(name)
			fx._syncing = true
			if Opts.FX_Scene then Opts.FX_Scene:SetValue(name) end
			fx._syncing = false

			local scene = fx.Scenes[name]
			SceneStatus:SetText(scene and string.format('%s · %s · %s', name, scene.Category or '', scene.Weight or '') or 'No scene - clean UI')
		end

		table.insert(fx.SceneListeners, SceneChanged)
		SceneChanged(fx.SceneName) -- the default theme may already have picked a scene before these controls existed

		Section(Engine, 'Presets')

		Engine:AddSelector('FX_Preset', {
			Text = 'Visual preset', Values = { 'Vanguard', 'Clean', 'Dark', 'Ocean', 'Sakura', 'Cyber', 'Inferno' }, Default = 'Vanguard',
			Callback = function(v)
				if fx._syncing then return end

				local theme = ({ Vanguard = 'Vanguard', Clean = 'Default', Dark = 'Void', Ocean = 'Ocean', Sakura = 'Sakura', Cyber = 'Cyber', Inferno = 'Inferno' })[v]
				if theme and Opts.ThemeManager_ThemeList then
					Opts.ThemeManager_ThemeList:SetValue(theme)
				end
			end,
		})

		-- ================= Visual Lab (UI only) =================
		-- Everything here only changes how THIS window is drawn. No game objects, remotes or gameplay are touched.
		local Lab = tab:AddRightGroupbox('Visual Lab (UI only)')

		Section(Lab, 'Window effects')

		Lab:AddToggle('Lab_Glow', { Text = 'Glow Mode', Default = false, Tooltip = 'UI only: accent glow around this window', Callback = function(v)
			if lib.Window then lib.Window:SetGlowMode(v) end
		end })

		Lab:AddToggle('Lab_RGB', { Text = 'RGB Border', Default = false, Tooltip = 'UI only: rainbow window border', Callback = function(v)
			if lib.Window then lib.Window:SetRGBBorder(v) end
		end })

		Lab:AddToggle('Lab_Cinematic', { Text = 'Cinematic Mode', Default = false, Tooltip = 'UI only: dark vignette and slower effects', Callback = function(v)
			if lib.Window then lib.Window:SetCinematic(v) end
		end }):AddKeyPicker('Lab_Cinematic Key', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Cinematic Mode', NoUI = false })

		Section(Lab, 'Tuning')

		local GlowMore = Lab:AddAdvanced('Glow options')

		local function RefreshGlow()
			if lib.GlowMode and lib.Window then lib.Window:SetGlowMode(true) end
		end

		GlowMore:AddSlider('Lab_GlowStrength', { Text = 'Glow strength', Default = 2, Min = 1, Max = 3, Rounding = 1, Callback = function(v)
			lib.GlowStrength = v
			RefreshGlow()
		end })

		GlowMore:AddChecklist('Lab_GlowParts', { Text = 'Glow applies to', Values = { 'Shadow', 'Border' }, Default = { 'Shadow', 'Border' }, Callback = function(v)
			lib.GlowParts = v
			RefreshGlow()
		end })

		-- ================= System =================
		local Sys = tab:AddRightGroupbox('System')

		Section(Sys, 'Monitors')

		Sys:AddGraph('Sys_FPS', { Text = 'Performance Monitor', Min = 0, Max = 120, Suffix = ' fps', Sample = function() return lib.FPS end })

		Sys:AddGraph('Sys_Ping', { Text = 'Network Visualizer', Min = 0, Max = 300, Suffix = ' ms', Sample = function()
			local ok, ping = pcall(function() return game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue() end)
			return ok and ping or 0
		end })

		Section(Sys, 'Engine')

		local EngineStatus = Sys:AddLabel('Theme engine: idle')

		-- refresh the status line once a second, only while the menu is open
		local Elapsed, LastText = 0, ''
		lib:GiveSignal(game:GetService('RunService').Heartbeat:Connect(function(dt)
			Elapsed = Elapsed + dt
			if Elapsed < 1 or not lib.Toggled then return end
			Elapsed = 0

			local s = fx:GetStats()
			local text = string.format('Engine: %s · %s · %d particles', s.Scene, s.Running and 'running' or 'idle', s.Particles)
			if text ~= LastText then
				LastText = text
				EngineStatus:SetText(text)
			end
		end))

		Section(Sys, 'Tools')

		Sys:AddButton({ Text = 'Run UI diagnostics', Tooltip = 'Prints the engine state', Func = function()
			local s = fx:GetStats()
			lib:Notify(string.format('Scene: %s | %s | intensity %s | %s', s.Scene, s.Performance, s.Intensity, s.Running and 'running' or 'idle'), 5)
			lib:Notify(string.format('Particles: %d | tweens: %d | scripted: %d | budget scale: %.2f', s.Particles, s.Tweens, s.Updaters, s.AutoScale), 5)
			lib:Notify(string.format('Frame: %.1f ms (%d fps) | themed objects: %d', s.FrameMs, math.floor(lib.FPS + 0.5), #lib.Registry), 5)
		end })
	end

	function ThemeManager:CreateGroupBox(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		return tab:AddLeftGroupbox('Themes')
	end

	function ThemeManager:ApplyToTab(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		local groupbox = self:CreateGroupBox(tab)
		self:CreateThemeManager(groupbox)

		-- visual engine controls (set ThemeManager.VisualUI = false to keep only the color themes)
		if self.VisualUI ~= false and self.Library.FX then
			self:CreateVisualUI(tab)
		end
	end

	function ThemeManager:ApplyToGroupbox(groupbox)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		self:CreateThemeManager(groupbox)
	end

	ThemeManager:BuildFolderTree()
end

return ThemeManager
