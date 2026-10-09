local cloneref = cloneref or function(o) return o end
local workspace = cloneref(game:GetService('Workspace'));
local InputService: UserInputService = cloneref(game:GetService('UserInputService'));
local TextService: TextService = cloneref(game:GetService('TextService'));
local CoreGui: CoreGui = cloneref(game:GetService('CoreGui'));
local Teams: Teams = cloneref(game:GetService('Teams'));
local Players: Players = cloneref(game:GetService('Players'));
local RunService: RunService = cloneref(game:GetService('RunService'));
local TweenService: TweenService = cloneref(game:GetService('TweenService'));
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);
local GetHUI = gethui or (function() return CoreGui end);
local IsKrampus = ((identifyexecutor or (function() return "" end))():lower() == "krampus");

local ScreenGui = Instance.new('ScreenGui');
ScreenGui.Name = "Core";
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
ScreenGui.Parent = GetHUI();

local Toggles = {};
local Options = {};

getgenv().Linoria = { 
	Toggles = Toggles,
	Options = Options
}

getgenv().Toggles = Toggles; -- if you load infinite yeild after you executed any script with LinoriaLib it will just break the whole UI lib :/ (thats why I added getgenv().Linoria)
getgenv().Options = Options;

local LibraryMainOuterFrame = nil;
local Library = {
	Registry = {};
	RegistryMap = {};

	HudRegistry = {};

	FontColor = Color3.fromRGB(225, 225, 232);
	DimFontColor = Color3.fromRGB(140, 140, 152);
	MainColor = Color3.fromRGB(22, 22, 28);
	BackgroundColor = Color3.fromRGB(14, 14, 19);
	SelectedColor = Color3.fromRGB(30, 24, 44);
	AccentColor = Color3.fromRGB(140, 85, 210);
	OutlineColor = Color3.fromRGB(46, 46, 56);
	CornerRadius = 6;
	RiskColor = Color3.fromRGB(255, 70, 85),

	Black = Color3.new(0, 0, 0);
	Font = Enum.Font.Gotham,
	FontBold = Enum.Font.GothamBold,
	FontMedium = Enum.Font.GothamMedium,

	-- animation tuning: everything eases with Quint so motion feels smooth instead of snappy
	AnimationSpeed = 1; -- >1 = slower, <1 = faster
	AnimatedBorder = true; -- slow accent sweep around the window border
	Shadows = false; -- soft drop shadow around the window / loading card (CreateWindow({ Shadow = true }) turns it on)

	OpenedFrames = {};
	DependencyBoxes = {};

	Signals = {};
	ScreenGui = ScreenGui;
	
	ActiveTab = nil;
	Toggled = false;
	
	MinSize = Vector2.new(600, 300);
	IsMobile = false;
	DevicePlatform = Enum.Platform.None;
	CanDrag = true;
	CantDragForced = false;
	ShowCustomCursor = false; 
	VideoLink = "";
	TotalTabs = 0;
};

pcall(function() Library.DevicePlatform = InputService:GetPlatform(); end); -- For safety so the UI library doesn't error.
Library.IsMobile = (Library.DevicePlatform == Enum.Platform.Android or Library.DevicePlatform == Enum.Platform.IOS)
	-- GetPlatform can be blocked on some executors: a touch screen without a keyboard is a phone / tablet too
	or (InputService.TouchEnabled and not InputService.KeyboardEnabled);

if Library.IsMobile then
	Library.MinSize = Vector2.new(600, 200); -- Make UI little bit smaller.
end

-- Bigger touch targets on phones / tablets: TouchSize(22) -> 30 on mobile, 22 on PC
Library.TouchScale = Library.IsMobile and 1.35 or 1;

local function TouchSize(Size)
	return math.floor(Size * Library.TouchScale + 0.5);
end;

local RainbowStep = 0
local Hue = 0
local FpsTime, FpsFrames = 0, 0
Library.FPS = 60

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
	RainbowStep = RainbowStep + Delta

	-- measured frame rate (used by the performance graph); updates twice a second
	FpsTime = FpsTime + Delta
	FpsFrames = FpsFrames + 1
	if FpsTime >= 0.5 then
		Library.FPS = FpsFrames / FpsTime
		FpsTime, FpsFrames = 0, 0
	end

	if RainbowStep >= (1 / 60) then
		RainbowStep = 0;

		Hue = Hue + (1 / 400);

		if Hue > 1 then
			Hue = 0;
		end;

		Library.CurrentRainbowHue = Hue;
		Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);
	end;
end));

local function GetPlayersString()
	local PlayerList = Players:GetPlayers();

	for i = 1, #PlayerList do
		PlayerList[i] = PlayerList[i].Name;
	end;

	table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

	return PlayerList;
end;

local function GetTeamsString()
	local TeamList = Teams:GetTeams();

	for i = 1, #TeamList do
		TeamList[i] = TeamList[i].Name;
	end;

	table.sort(TeamList, function(str1, str2) return str1 < str2 end);
	
	return TeamList;
end;

function Library:SafeCallback(f, ...)
	if (not f) then
		return;
	end;

	if not Library.NotifyOnError then
		return f(...);
	end;

	local success, event = pcall(f, ...);

	if not success then
		local _, i = event:find(":%d+: ");

		if not i then
			return Library:Notify(event);
		end;

		return Library:Notify(event:sub(i + 1), 3);
	end;
end;

-- Lets several scripts listen to the same :OnChanged (ThemeManager + SaveManager etc.)
function Library:ChainCallback(Old, New)
	if type(Old) ~= 'function' then
		return New;
	end;

	return function(...)
		Library:SafeCallback(Old, ...);
		return New(...);
	end;
end;

-- ===== Animation helpers =====
Library.TweenCache = setmetatable({}, { __mode = 'k' });

-- Smoothly tween properties; re-calling with the same target is a no-op, a new target cancels the old tween.
function Library:Tween(Inst, Props, Time, Style, Dir)
	if not Inst then
		return;
	end;

	local Cache = Library.TweenCache[Inst];
	if not Cache then
		Cache = {};
		Library.TweenCache[Inst] = Cache;
	end;

	if Time == 0 then
		for Prop, Value in next, Props do
			Library:SetNow(Inst, Prop, Value);
		end;
		return;
	end;

	local Info = TweenInfo.new((Time or 0.2) * Library.AnimationSpeed, Style or Enum.EasingStyle.Quint, Dir or Enum.EasingDirection.Out);

	for Prop, Value in next, Props do
		local Entry = Cache[Prop];

		if Entry and Entry.Target == Value then
			-- already heading there
		elseif (not Entry) and Inst[Prop] == Value then
			-- already there
		else
			if Entry then
				Entry.Tween:Cancel();
			end;

			local NewTween = TweenService:Create(Inst, Info, { [Prop] = Value });
			local NewEntry = { Target = Value; Tween = NewTween; };
			Cache[Prop] = NewEntry;

			NewTween.Completed:Connect(function()
				if Cache[Prop] == NewEntry then
					Cache[Prop] = nil;
				end;
			end);

			NewTween:Play();
		end;
	end;
end;

-- Set a property immediately and cancel any running tween on it
function Library:SetNow(Inst, Prop, Value)
	local Cache = Library.TweenCache[Inst];
	if Cache and Cache[Prop] then
		Cache[Prop].Tween:Cancel();
		Cache[Prop] = nil;
	end;
	Inst[Prop] = Value;
end;

Library.FadeState = setmetatable({}, { __mode = 'k' });

local function GetFadeProps(Obj)
	if Obj:IsA('TextLabel') or Obj:IsA('TextBox') or Obj:IsA('TextButton') then
		return { 'TextTransparency', 'BackgroundTransparency' };
	elseif Obj:IsA('ImageLabel') or Obj:IsA('ImageButton') then
		return { 'ImageTransparency', 'BackgroundTransparency' };
	elseif Obj:IsA('GuiObject') then
		return { 'BackgroundTransparency' };
	elseif Obj:IsA('UIStroke') then
		return { 'Transparency' };
	end;
end;

local function CaptureFade(Frame, State)
	State.Orig = {};

	local List = Frame:GetDescendants();
	table.insert(List, Frame);

	for _, Obj in next, List do
		local Props = GetFadeProps(Obj);
		if Props then
			for _, Prop in next, Props do
				local Value = Obj[Prop];
				if Value < 1 then
					State.Orig[Obj] = State.Orig[Obj] or {};
					State.Orig[Obj][Prop] = Value;
				end;
			end;
		end;
	end;
end;

local function RunFade(State, Info, ToHidden)
	for _, T in next, State.Tweens do
		T:Cancel();
	end;
	State.Tweens = {};

	for Obj, Props in next, State.Orig do
		for Prop, Value in next, Props do
			local T = TweenService:Create(Obj, Info, { [Prop] = ToHidden and 1 or Value });
			table.insert(State.Tweens, T);
			T:Play();
		end;
	end;
end;

-- Fade a popup frame (and everything inside it) in/out instead of popping it.
-- Popups also get a small "pop" scale so they grow out of where they were opened.
function Library:FadeFrame(Frame, Show, Time)
	Time = (Show and math.max(Time or 0, 0.24) or math.max(Time or 0, 0.16)) * Library.AnimationSpeed;

	local State = Library.FadeState[Frame];
	if not State then
		State = { Orig = {}; Tweens = {}; Mode = nil; Token = 0; };
		Library.FadeState[Frame] = State;
	end;

	local Scale = Frame:FindFirstChild('PopScale');
	if not Scale then
		Scale = Instance.new('UIScale');
		Scale.Name = 'PopScale';
		Scale.Parent = Frame;
	end;

	local Info = TweenInfo.new(Time, Enum.EasingStyle.Quint, Show and Enum.EasingDirection.Out or Enum.EasingDirection.In);

	if Show then
		if State.Mode == 'in' or (State.Mode == nil and Frame.Visible) then
			return;
		end;

		if State.Mode ~= 'out' then
			CaptureFade(Frame, State);
			for Obj, Props in next, State.Orig do
				for Prop in next, Props do
					Obj[Prop] = 1;
				end;
			end;
			Scale.Scale = 0.94;
			Frame.Visible = true;
		end;

		State.Mode = 'in';
		State.Token = State.Token + 1;
		local Token = State.Token;
		RunFade(State, Info, false);
		local ScaleTween = TweenService:Create(Scale, TweenInfo.new(Time * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 });
		table.insert(State.Tweens, ScaleTween);
		ScaleTween:Play();

		task.delay(Time, function()
			if State.Token == Token and State.Mode == 'in' then
				State.Mode = nil;
			end;
		end);
	else
		if State.Mode == 'out' or (State.Mode == nil and not Frame.Visible) then
			return;
		end;

		if State.Mode == nil then
			CaptureFade(Frame, State);
		end;

		State.Mode = 'out';
		State.Token = State.Token + 1;
		local Token = State.Token;
		RunFade(State, Info, true);
		local ScaleTween = TweenService:Create(Scale, Info, { Scale = 0.96 });
		table.insert(State.Tweens, ScaleTween);
		ScaleTween:Play();

		task.delay(Time, function()
			if State.Token == Token and State.Mode == 'out' then
				State.Mode = nil;
				Frame.Visible = false;
				Scale.Scale = 1;

				for Obj, Props in next, State.Orig do
					for Prop, Value in next, Props do
						Obj[Prop] = Value;
					end;
				end;
			end;
		end);
	end;
end;
-- ===== end animation helpers =====

function Library:AttemptSave()
	if Library.SaveManager then
		Library.SaveManager:Save();
	end;
end;

function Library:Create(Class, Properties)
	local _Instance = Class;

	if type(Class) == 'string' then
		_Instance = Instance.new(Class);
	end;

	if _Instance:IsA('UICorner') and Properties.CornerRadius == nil then
		Properties.CornerRadius = UDim.new(0, Library.CornerRadius or 0);
	end;

	for Property, Value in next, Properties do
		_Instance[Property] = Value;
	end;

	return _Instance;
end;

-- ===== Style helpers =====
function Library:AddCorner(Inst, Radius)
	return Library:Create('UICorner', {
		CornerRadius = UDim.new(0, Radius or Library.CornerRadius);
		Parent = Inst;
	});
end;

-- Outline drawn with a UIStroke (smooth on rounded corners) and kept in sync with the theme
function Library:AddStroke(Inst, ColorIdx, Thickness, Transparency)
	ColorIdx = ColorIdx or 'BorderColor';

	local Stroke = Library:Create('UIStroke', {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
		Color = Library[ColorIdx] or ColorIdx;
		LineJoinMode = Enum.LineJoinMode.Round;
		Thickness = Thickness or 1;
		Transparency = Transparency or 0;
		Parent = Inst;
	});

	if type(ColorIdx) == 'string' then
		Library:AddToRegistry(Stroke, { Color = ColorIdx; });
	end;

	return Stroke;
end;

-- Subtle top-to-bottom sheen used on buttons / inputs
function Library:AddSheen(Inst, Amount)
	return Library:Create('UIGradient', {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1):Lerp(Color3.new(0, 0, 0), Amount or 0.12))
		});
		Rotation = 90;
		Parent = Inst;
	});
end;

-- BorderColor = the color every outline / divider actually uses.
-- Many themes set OutlineColor darker than (or almost equal to) the surfaces, e.g. 141414 on 1e1e1e,
-- which makes borders vanish on a dark UI. So: use OutlineColor only if it is clearly *lighter* than
-- the brightest surface, otherwise derive a line color by tinting that surface toward the font color.
local function Luma(Color)
	return 0.299 * Color.R + 0.587 * Color.G + 0.114 * Color.B;
end;

function Library:ComputeBorderColor()
	local Base = Library.MainColor;
	if Luma(Library.BackgroundColor) > Luma(Base) then
		Base = Library.BackgroundColor;
	end;

	if Luma(Library.OutlineColor) - Luma(Base) >= 0.06 then
		return Library.OutlineColor;
	end;

	return Base:Lerp(Library.FontColor, 0.15);
end;

Library.BorderColor = Library:ComputeBorderColor();

-- kept for scripts that want a divider color
function Library:GetSeparatorColor()
	return Library.BorderColor;
end;

-- CanvasGroup when the engine supports it (lets us fade a whole tree with one property), plain Frame otherwise
function Library:CreateCanvas(Properties)
	local Ok, Canvas = pcall(Instance.new, 'CanvasGroup');
	if not Ok then
		Canvas = Instance.new('Frame');
		Canvas.ClipsDescendants = true;
	end;

	return Library:Create(Canvas, Properties);
end;

function Library:SetGroupTransparency(Canvas, Value, Time, Style, Dir)
	if not Canvas:IsA('CanvasGroup') then
		return;
	end;

	if Time then
		Library:Tween(Canvas, { GroupTransparency = Value }, Time, Style, Dir);
	else
		Library:SetNow(Canvas, 'GroupTransparency', Value);
	end;
end;

-- Soft drop shadow behind a frame
function Library:AddShadow(Inst, Spread, Transparency)
	Spread = Spread or 18;

	return Library:Create('ImageLabel', {
		Name = 'Shadow';
		AnchorPoint = Vector2.new(0.5, 0.5);
		BackgroundTransparency = 1;
		Image = 'rbxassetid://6014261993';
		ImageColor3 = Color3.new(0, 0, 0);
		ImageTransparency = Transparency or 0.45;
		Position = UDim2.new(0.5, 0, 0.5, 4);
		ScaleType = Enum.ScaleType.Slice;
		SliceCenter = Rect.new(49, 49, 450, 450);
		Size = UDim2.new(1, Spread * 2, 1, Spread * 2);
		ZIndex = math.max(Inst.ZIndex - 1, 0);
		Parent = Inst;
	});
end;

-- Material-style ripple from the click point
function Library:Ripple(Holder, X, Y)
	local Size = math.max(Holder.AbsoluteSize.X, Holder.AbsoluteSize.Y) * 2.2;

	local Circle = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5);
		BackgroundColor3 = Library.AccentColor;
		BackgroundTransparency = 0.65;
		BorderSizePixel = 0;
		Position = UDim2.fromOffset(X - Holder.AbsolutePosition.X, Y - Holder.AbsolutePosition.Y);
		Size = UDim2.fromOffset(0, 0);
		ZIndex = Holder.ZIndex + 1;
		Parent = Holder;
	});
	Library:AddCorner(Circle, 9999);

	local Info = TweenInfo.new(0.6 * Library.AnimationSpeed, Enum.EasingStyle.Quint, Enum.EasingDirection.Out);
	TweenService:Create(Circle, Info, { Size = UDim2.fromOffset(Size, Size); BackgroundTransparency = 1; }):Play();
	task.delay(0.6 * Library.AnimationSpeed, function()
		Circle:Destroy();
	end);
end;

-- Squish-and-bounce feedback when something is pressed
function Library:Press(Scale)
	if not Scale then
		return;
	end;

	Library:SetNow(Scale, 'Scale', Scale.Scale);
	TweenService:Create(Scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.965 }):Play();
	task.delay(0.08, function()
		TweenService:Create(Scale, TweenInfo.new(0.35 * Library.AnimationSpeed, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play();
	end);
end;
-- ===== Pointer helpers (mouse + touch) =====
local function IsTouch(Input)
	return Input and Input.UserInputType == Enum.UserInputType.Touch;
end;

local function IsPress(Input)
	return Input and (Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch);
end;

-- Pointer position in the same space as AbsolutePosition
function Library:GetPointer(Input)
	if IsTouch(Input) then
		return Input.Position.X, Input.Position.Y;
	end;

	return Mouse.X, Mouse.Y;
end;

-- Calls Callback(X, Y) every frame while the press that started with `Input` is held.
-- The old loops used IsMouseButtonPressed(MouseButton1 or Touch), which in Lua is just MouseButton1,
-- so sliders / color pickers stopped instantly on phones.
function Library:TrackPointer(Input, Callback)
	local Touch = IsTouch(Input);

	while true do
		local Held;

		if Touch then
			Held = Input.UserInputState ~= Enum.UserInputState.End and Input.UserInputState ~= Enum.UserInputState.Cancel;
		else
			Held = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1);
		end;

		if not Held then
			break;
		end;

		Callback(Library:GetPointer(Input));
		RenderStepped:Wait();
	end;
end;

-- Click with the mouse fires immediately; on touch it fires on *release*, and only if the finger
-- barely moved and wasn't held long. Otherwise starting a scroll on a toggle would flip it.
function Library:OnTap(Inst, Callback)
	Inst.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			Callback(Input);
			return;
		end;

		if not IsTouch(Input) then
			return;
		end;

		local StartPos = Input.Position;
		local StartTime = os.clock();
		local Connection;

		Connection = Input:GetPropertyChangedSignal('UserInputState'):Connect(function()
			local State = Input.UserInputState;
			if State ~= Enum.UserInputState.End and State ~= Enum.UserInputState.Cancel then
				return;
			end;

			Connection:Disconnect();

			if State == Enum.UserInputState.End and (Input.Position - StartPos).Magnitude < 12 and os.clock() - StartTime < 0.45 then
				Callback(Input);
			end;
		end);
	end);
end;

-- Long-press (touch) stands in for right-click / hover on phones
function Library:OnLongPress(Inst, Callback, Time)
	Inst.InputBegan:Connect(function(Input)
		if not IsTouch(Input) then
			return;
		end;

		local StartX, StartY = Input.Position.X, Input.Position.Y;
		task.delay(Time or 0.45, function()
			local Moved = math.abs(Input.Position.X - StartX) + math.abs(Input.Position.Y - StartY) > 12;

			if Input.UserInputState ~= Enum.UserInputState.End and Input.UserInputState ~= Enum.UserInputState.Cancel and not Moved then
				Callback(Input);
			end;
		end);
	end);
end;
-- ===== end pointer helpers =====
-- ===== end style helpers =====

function Library:ApplyTextStroke(Inst)
	Inst.TextStrokeTransparency = 1;
end;

function Library:CreateLabel(Properties, IsHud)
	local _Instance = Library:Create('TextLabel', {
		BackgroundTransparency = 1;
		Font = Library.Font;
		TextColor3 = Library.FontColor;
		TextSize = 16;
		TextStrokeTransparency = 0;
	});

	Library:ApplyTextStroke(_Instance);

	Library:AddToRegistry(_Instance, {
		TextColor3 = 'FontColor';
	}, IsHud);

	return Library:Create(_Instance, Properties);
end;

function Library:MakeDraggable(Instance, Cutoff)
	Instance.Active = true;

	Instance.InputBegan:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			local ObjPos = Vector2.new(
				Mouse.X - Instance.AbsolutePosition.X,
				Mouse.Y - Instance.AbsolutePosition.Y
			);

			if ObjPos.Y > (Cutoff or 40) then
				return;
			end;

			while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
				-- short tween toward the cursor = buttery drag with a tiny bit of trailing
				Library:Tween(Instance, {
					Position = UDim2.new(
						0,
						Mouse.X - ObjPos.X + (Instance.Size.X.Offset * Instance.AnchorPoint.X),
						0,
						Mouse.Y - ObjPos.Y + (Instance.Size.Y.Offset * Instance.AnchorPoint.Y)
					);
				}, 0.12, Enum.EasingStyle.Quint);

				RenderStepped:Wait();
			end;
		end;
	end);

	if Library.IsMobile then
		local Dragging, DraggingInput, DraggingStart, StartPosition;

		InputService.TouchStarted:Connect(function(Input)
			if Library.CantDragForced == true then
				Dragging = false
				return;
			end
			-- only start a drag from the top strip (header) of the frame, so tapping buttons / scrolling never moves it
			-- (the old check compared the touch with itself, so the whole window was a drag handle)
			if not Dragging and Instance.Visible and Library:MouseIsOverFrame(Instance, Input) then
				if Input.Position.Y - Instance.AbsolutePosition.Y > (Cutoff or 40) then
					return;
				end;

				DraggingInput = Input;
				DraggingStart = Input.Position;
				StartPosition = Instance.Position;
				Dragging = true;
			end;
		end);
		InputService.TouchMoved:Connect(function(Input)
			if Library.CantDragForced == true then
				Dragging = false;
				return;
			end
			if Input == DraggingInput and Dragging and Library.CanDrag == true and Instance.Visible then
				local OffsetPos = Input.Position - DraggingStart;

				Library:Tween(Instance, {
					Position = UDim2.new(
						StartPosition.X.Scale,
						StartPosition.X.Offset + OffsetPos.X,
						StartPosition.Y.Scale,
						StartPosition.Y.Offset + OffsetPos.Y
					);
				}, 0.08);
			end;
		end);
		InputService.TouchEnded:Connect(function(Input)
			if Input == DraggingInput then 
				Dragging = false;
			end;
		end);
	end;
end;

function Library:MakeResizable(Instance, MinSize, GripParent)
	if Library.IsMobile then
		return;
	end;

	MinSize = MinSize or Library.MinSize;

	local GripSize = 18;

	local Grip = Library:Create('TextButton', {
		AnchorPoint = Vector2.new(1, 1);
		BackgroundTransparency = 1;
		AutoButtonColor = false;
		Text = '';
		Position = UDim2.new(1, -3, 1, -3);
		Size = UDim2.fromOffset(GripSize, GripSize);
		ZIndex = 50;
		Parent = GripParent or Instance;
	});

	-- little diagonal dot pattern in the bottom-right corner
	local Dots = { {12, 12}, {8, 12}, {12, 8}, {4, 12}, {8, 8}, {12, 4} };
	local DotFrames = {};
	for _, Pos in next, Dots do
		local Dot = Library:Create('Frame', {
			BackgroundColor3 = Library.AccentColor;
			BackgroundTransparency = 0.5;
			BorderSizePixel = 0;
			Position = UDim2.fromOffset(Pos[1], Pos[2]);
			Size = UDim2.fromOffset(2, 2);
			ZIndex = 51;
			Parent = Grip;
		});
		Library:AddCorner(Dot, 1);
		Library:AddToRegistry(Dot, { BackgroundColor3 = 'AccentColor'; });
		table.insert(DotFrames, Dot);
	end;

	Grip.MouseEnter:Connect(function()
		for _, Dot in next, DotFrames do
			Library:Tween(Dot, { BackgroundTransparency = 0 }, 0.2);
		end;
	end);

	Grip.MouseLeave:Connect(function()
		for _, Dot in next, DotFrames do
			Library:Tween(Dot, { BackgroundTransparency = 0.5 }, 0.3);
		end;
	end);

	local Resizing = false;
	local StartMouse, StartSize;

	local function IsPress(Input)
		return Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch;
	end;

	Grip.InputBegan:Connect(function(Input)
		if IsPress(Input) then
			Resizing = true;
			StartMouse = Vector2.new(Input.Position.X, Input.Position.Y);
			StartSize = Instance.AbsoluteSize;
		end;
	end);

	Library:GiveSignal(InputService.InputChanged:Connect(function(Input)
		if not Resizing then
			return;
		end;

		if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
			local Delta = Vector2.new(Input.Position.X, Input.Position.Y) - StartMouse;
			local Screen = Library.ScreenGui.AbsoluteSize;

			local NewX = math.clamp(StartSize.X + Delta.X, MinSize.X, math.max(MinSize.X, Screen.X));
			local NewY = math.clamp(StartSize.Y + Delta.Y, MinSize.Y, math.max(MinSize.Y, Screen.Y));

			Library:Tween(Instance, { Size = UDim2.fromOffset(NewX, NewY) }, 0.1);
		end;
	end));

	Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
		if Resizing and IsPress(Input) then
			Resizing = false;
		end;
	end));
end;

function Library:CreateLoadingScreen(Info)
	Info = Info or {};

	local LoadingScreenOuter = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5);
		BackgroundTransparency = 1;
		Position = UDim2.fromScale(0.5, 0.5);
		Size = UDim2.fromOffset(360, 170);
		ZIndex = 1000;
		Parent = ScreenGui;
	});

	local Shadow = Library:AddShadow(LoadingScreenOuter, 26, 0.35);
	Shadow.Visible = Library.Shadows == true;
	local ShadowTransparency = Shadow.ImageTransparency;
	Shadow.ImageTransparency = 1;

	local PopScale = Library:Create('UIScale', {
		Scale = 0.9;
		Parent = LoadingScreenOuter;
	});

	local Card = Library:CreateCanvas({
		BackgroundColor3 = Library.BackgroundColor;
		BorderSizePixel = 0;
		Size = UDim2.fromScale(1, 1);
		ZIndex = 1001;
		Parent = LoadingScreenOuter;
	});
	Library:AddCorner(Card, 10);
	Library:AddToRegistry(Card, { BackgroundColor3 = 'BackgroundColor'; });
	Library:SetGroupTransparency(Card, 1);

	local Border = Library:Create('Frame', {
		BackgroundTransparency = 1;
		Size = UDim2.fromScale(1, 1);
		ZIndex = 1010;
		Parent = LoadingScreenOuter;
	});
	Library:AddCorner(Border, 10);
	local BorderStroke = Library:AddStroke(Border, 'BorderColor');
	BorderStroke.Transparency = 1;

	-- glowing accent line along the top edge
	local TopLine = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Size = UDim2.new(1, 0, 0, 2);
		ZIndex = 1002;
		Parent = Card;
	});
	Library:AddToRegistry(TopLine, { BackgroundColor3 = 'AccentColor'; });
	Library:Create('UIGradient', {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		});
		Parent = TopLine;
	});

	if Info.Title then
		Library:CreateLabel({
			Position = UDim2.new(0, 0, 0, 30);
			Size = UDim2.new(1, 0, 0, 22);
			Font = Library.FontBold;
			Text = Info.Title;
			TextSize = 18;
			ZIndex = 1004;
			Parent = Card;
		});
	end

	if Info.Subtitle then
		local SubtitleLabel = Library:CreateLabel({
			Position = UDim2.new(0, 0, 0, 56);
			Size = UDim2.new(1, 0, 0, 16);
			Text = Info.Subtitle;
			TextSize = 13;
			ZIndex = 1004;
			Parent = Card;
		});
		SubtitleLabel.TextColor3 = Library.DimFontColor;
		Library.RegistryMap[SubtitleLabel].Properties.TextColor3 = 'DimFontColor';
	end

	local Track = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderSizePixel = 0;
		ClipsDescendants = true;
		Position = UDim2.new(0, 32, 0, 98);
		Size = UDim2.new(1, -64, 0, 6);
		ZIndex = 1004;
		Parent = Card;
	});
	Library:AddCorner(Track, 3);
	Library:AddToRegistry(Track, { BackgroundColor3 = 'MainColor'; });

	local LoadingBarFill = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.new(-0.35, 0, 0, 0);
		Size = UDim2.new(0.35, 0, 1, 0);
		ZIndex = 1005;
		Parent = Track;
	});
	Library:AddCorner(LoadingBarFill, 3);
	Library:AddToRegistry(LoadingBarFill, { BackgroundColor3 = 'AccentColor'; });

	-- moving highlight across the fill
	local Shimmer = Library:Create('UIGradient', {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 200, 200)),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
		});
		Offset = Vector2.new(-1, 0);
		Parent = LoadingBarFill;
	});

	local ShimmerTween = TweenService:Create(Shimmer, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) });
	ShimmerTween:Play();

	local StatusText;
	if Info.Status then
		StatusText = Library:CreateLabel({
			Position = UDim2.new(0, 0, 0, 116);
			Size = UDim2.new(1, 0, 0, 16);
			Text = Info.Status;
			TextSize = 12;
			ZIndex = 1004;
			Parent = Card;
		});
		StatusText.TextColor3 = Library.DimFontColor;
		Library.RegistryMap[StatusText].Properties.TextColor3 = 'DimFontColor';
	end

	-- indeterminate: a segment gliding back and forth until a real progress value comes in
	local LoadingTween = TweenService:Create(LoadingBarFill,
		TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(1, 0, 0, 0) }
	);
	LoadingTween:Play();

	-- entrance
	Library:SetGroupTransparency(Card, 0, 0.45);
	Library:Tween(BorderStroke, { Transparency = 0 }, 0.45);
	Library:Tween(Shadow, { ImageTransparency = ShadowTransparency }, 0.6);
	TweenService:Create(PopScale, TweenInfo.new(0.6 * Library.AnimationSpeed, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play();

	local Destroyed = false;

	Library.LoadingScreen = {
		Outer = LoadingScreenOuter,
		Bar = LoadingBarFill,
		StatusText = StatusText,
		Destroy = function()
			if Destroyed then return end
			Destroyed = true;
			Library.LoadingScreen = nil;

			Library:SetGroupTransparency(Card, 1, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			Library:Tween(BorderStroke, { Transparency = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			Library:Tween(Shadow, { ImageTransparency = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			Library:Tween(PopScale, { Scale = 0.94 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In);

			task.delay(0.32 * Library.AnimationSpeed, function()
				LoadingTween:Cancel();
				ShimmerTween:Cancel();
				LoadingScreenOuter:Destroy();
			end);
		end,
		SetStatus = function(Text)
			if StatusText then
				StatusText.Text = Text;
			end
		end,
		SetProgress = function(Progress)
			LoadingTween:Cancel();
			Library:Tween(LoadingBarFill, {
				Position = UDim2.new(0, 0, 0, 0);
				Size = UDim2.new(math.clamp(Progress, 0, 1), 0, 1, 0);
			}, 0.45);
		end
	};
	return Library.LoadingScreen;
end

function Library:AddToolTip(InfoStr, HoverInstance)
	local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 13);
	local Tooltip = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor,
		BorderSizePixel = 0,

		Size = UDim2.fromOffset(X + 16, Y + 10),
		ZIndex = 100,
		Parent = Library.ScreenGui,

		Visible = false,
	});

	Library:AddCorner(Tooltip, 5);
	Library:AddStroke(Tooltip, 'BorderColor');

	local Label = Library:CreateLabel({
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.fromOffset(X, Y);
		TextSize = 13;
		Text = InfoStr,
		TextColor3 = Library.FontColor,
		TextXAlignment = Enum.TextXAlignment.Left;
		ZIndex = Tooltip.ZIndex + 1,

		Parent = Tooltip;
	});

	Library:AddToRegistry(Tooltip, {
		BackgroundColor3 = 'MainColor';
	});

	Library:AddToRegistry(Label, {
		TextColor3 = 'FontColor',
	});

	local IsHovering = false

	HoverInstance.MouseEnter:Connect(function()
		if Library:MouseIsOverOpenedFrame() then
			return
		end

		IsHovering = true

		Library:SetNow(Tooltip, 'Position', UDim2.fromOffset(Mouse.X + 16, Mouse.Y + 14))
		Library:FadeFrame(Tooltip, true)

		while IsHovering do
			RunService.Heartbeat:Wait()
			Library:Tween(Tooltip, { Position = UDim2.fromOffset(Mouse.X + 16, Mouse.Y + 14) }, 0.15)
		end
	end)

	HoverInstance.MouseLeave:Connect(function()
		IsHovering = false
		Library:FadeFrame(Tooltip, false)
	end)

	-- phones have no hover: long-press shows the tooltip above the finger until it is lifted
	Library:OnLongPress(HoverInstance, function(Input)
		local X, Y = Library:GetPointer(Input)
		local Size = Tooltip.AbsoluteSize

		Library:SetNow(Tooltip, 'Position', UDim2.fromOffset(math.max(X - Size.X / 2, 4), math.max(Y - Size.Y - 36, 4)))
		Library:FadeFrame(Tooltip, true)

		task.spawn(function()
			while Input.UserInputState ~= Enum.UserInputState.End and Input.UserInputState ~= Enum.UserInputState.Cancel do
				RenderStepped:Wait()
			end
			Library:FadeFrame(Tooltip, false)
		end)
	end)

	if LibraryMainOuterFrame then
		LibraryMainOuterFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if LibraryMainOuterFrame.Visible == false then
				IsHovering = false
				Tooltip.Visible = false
			end
		end)
	end
end

function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault, condition)
	local function undoHighlight()
		local Reg = Library.RegistryMap[Instance];

		for Property, ColorIdx in next, PropertiesDefault do
			Library:Tween(Instance, { [Property] = Library[ColorIdx] or ColorIdx }, 0.3);

			if Reg and Reg.Properties[Property] then
				Reg.Properties[Property] = ColorIdx;
			end;
		end;
	end
	local function doHighlight()
		if condition and not condition() then undoHighlight() return end
		local Reg = Library.RegistryMap[Instance];

		for Property, ColorIdx in next, Properties do
			Library:Tween(Instance, { [Property] = Library[ColorIdx] or ColorIdx }, 0.2);

			if Reg and Reg.Properties[Property] then
				Reg.Properties[Property] = ColorIdx;
			end;
		end;
	end

	HighlightInstance.MouseEnter:Connect(function()
		doHighlight()
	end)
	HighlightInstance.MouseMoved:Connect(function()
		doHighlight()
	end)
	HighlightInstance.MouseLeave:Connect(function()
		undoHighlight()
	end)
end;
function Library:MouseIsOverOpenedFrame(Input)
	local Pos = Mouse;
	if IsTouch(Input) then
		Pos = Input.Position;
	end;
	for Frame, _ in next, Library.OpenedFrames do
		local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

		if Pos.X >= AbsPos.X and Pos.X <= AbsPos.X + AbsSize.X
			and Pos.Y >= AbsPos.Y and Pos.Y <= AbsPos.Y + AbsSize.Y then

			return true;
		end;
	end;
end;

function Library:MouseIsOverFrame(Frame, Input)
	local Pos = Mouse;
	if IsTouch(Input) then
		Pos = Input.Position;
	end;
	local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

	if Pos.X >= AbsPos.X and Pos.X <= AbsPos.X + AbsSize.X
		and Pos.Y >= AbsPos.Y and Pos.Y <= AbsPos.Y + AbsSize.Y then

		return true;
	end;
end;

function Library:UpdateDependencyBoxes()
	for _, Depbox in next, Library.DependencyBoxes do
		Depbox:Update();
	end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
	return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
	local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
	return Bounds.X, Bounds.Y
end;

function Library:GetDarkerColor(Color)
	local H, S, V = Color3.toHSV(Color);
	return Color3.fromHSV(H, S, V / 1.5);
end;
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Instance, Properties, IsHud)
	local Idx = #Library.Registry + 1;
	local Data = {
		Instance = Instance;
		Properties = Properties;
		Idx = Idx;
	};

	table.insert(Library.Registry, Data);
	Library.RegistryMap[Instance] = Data;

	if IsHud then
		table.insert(Library.HudRegistry, Data);
	end;
end;

function Library:RemoveFromRegistry(Instance)
	local Data = Library.RegistryMap[Instance];

	if Data then
		for Idx = #Library.Registry, 1, -1 do
			if Library.Registry[Idx] == Data then
				table.remove(Library.Registry, Idx);
			end;
		end;

		for Idx = #Library.HudRegistry, 1, -1 do
			if Library.HudRegistry[Idx] == Data then
				table.remove(Library.HudRegistry, Idx);
			end;
		end;

		Library.RegistryMap[Instance] = nil;
	end;
end;

function Library:UpdateColorsUsingRegistry()
	-- derived from the theme colors, so it has to be refreshed first
	Library.BorderColor = Library:ComputeBorderColor();

	-- TODO: Could have an 'active' list of objects
	-- where the active list only contains Visible objects.

	-- IMPL: Could setup .Changed events on the AddToRegistry function
	-- that listens for the 'Visible' propert being changed.
	-- Visible: true => Add to active list, and call UpdateColors function
	-- Visible: false => Remove from active list.

	-- The above would be especially efficient for a rainbow menu color or live color-changing.

	for Idx, Object in next, Library.Registry do
		for Property, ColorIdx in next, Object.Properties do
			if type(ColorIdx) == 'string' then
				Object.Instance[Property] = Library[ColorIdx];
			elseif type(ColorIdx) == 'function' then
				Object.Instance[Property] = ColorIdx()
			end
		end;
	end;
end;

function Library:GiveSignal(Signal)
	-- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
	table.insert(Library.Signals, Signal)
end

function Library:Unload()
	-- Unload all of the signals
	for Idx = #Library.Signals, 1, -1 do
		local Connection = table.remove(Library.Signals, Idx)
		Connection:Disconnect()
	end

	-- Call every unload callback, maybe to undo some hooks etc
	for _, Callback in next, Library.UnloadCallbacks do
		task.spawn(Library.SafeCallback, Library, Callback)
	end

	ScreenGui:Destroy()
end

-- Several scripts can register (SaveManager + the game script); the old version
-- overwrote this method with the callback, so a second :OnUnload call ran the first callback instead.
Library.UnloadCallbacks = {};

function Library:OnUnload(Callback)
	if type(Callback) == 'function' then
		table.insert(Library.UnloadCallbacks, Callback);
	end
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
	if Library.RegistryMap[Instance] then
		Library:RemoveFromRegistry(Instance);
	end;
end))

local BaseAddons = {};

do
	local Funcs = {};

	function Funcs:AddColorPicker(Idx, Info)
		local ParentObj = self
		local ToggleLabel = self.TextLabel;
		--local Container = self.Container;

		assert(Info.Default, 'AddColorPicker: Missing default value.');

		local ColorPicker = {
			Value = Info.Default;
			Transparency = Info.Transparency or 0;
			Type = 'ColorPicker';
			Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
			Callback = Info.Callback or function(Color) end;
		};

		function ColorPicker:SetHSVFromRGB(Color)
			local H, S, V = Color3.toHSV(Color);

			ColorPicker.Hue = H;
			ColorPicker.Sat = S;
			ColorPicker.Vib = V;
		end;

		ColorPicker:SetHSVFromRGB(ColorPicker.Value);

		local DisplayFrame = Library:Create('Frame', {
			BackgroundColor3 = ColorPicker.Value;
			BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
			BorderSizePixel = 0;
			Size = UDim2.new(0, TouchSize(28), 0, TouchSize(14));
			ZIndex = 6;
			Parent = ToggleLabel;
		});

		Library:AddCorner(DisplayFrame, 4);
		local DisplayStroke = Library:AddStroke(DisplayFrame, Library:GetDarkerColor(ColorPicker.Value));

		DisplayFrame.MouseEnter:Connect(function()
			Library:Tween(DisplayStroke, { Thickness = 2 }, 0.2);
		end);
		DisplayFrame.MouseLeave:Connect(function()
			Library:Tween(DisplayStroke, { Thickness = 1 }, 0.25);
		end);

		local PickerFrameOuter = Library:Create('Frame', {
			Name = 'Color';
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 20),
			Size = UDim2.fromOffset(230, Info.Transparency and 273 or 255);
			Visible = false;
			ZIndex = 15;
			Parent = ScreenGui,
		});

		DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
			PickerFrameOuter.Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 20);
		end)

		local PickerFrameInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 16;
			Parent = PickerFrameOuter;
		});

		Library:AddCorner(PickerFrameInner, 8);
		Library:AddStroke(PickerFrameInner, 'BorderColor');

		local Highlight = Library:Create('Frame', {
			BackgroundColor3 = Library.AccentColor;
			BorderSizePixel = 0;
			Position = UDim2.new(0, 8, 0, 0);
			Size = UDim2.new(1, -16, 0, 2);
			ZIndex = 17;
			Parent = PickerFrameInner;
		});

		Library:Create('UIGradient', {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			});
			Parent = Highlight;
		});

		local SatVibMapOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			ClipsDescendants = true;
			Position = UDim2.new(0, 5, 0, 26);
			Size = UDim2.new(0, 200, 0, 200);
			ZIndex = 17;
			Parent = PickerFrameInner;
		});

		Library:AddCorner(SatVibMapOuter, 5);

		local SatVibMapInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 18;
			Parent = SatVibMapOuter;
		});

		Library:AddCorner(SatVibMapInner, 5);

		local SatVibMapContainer = Library:Create('Frame', {
		   BorderSizePixel = 0;
		   Size = UDim2.new(1, 0, 1, 0);
		   ZIndex = 18;
		   BackgroundColor3 = Color3.fromRGB(255, 255, 255);
		   Parent = SatVibMapInner;
		});
		
		local SatVibMapContainer = Library:Create('Frame', {
		    BorderSizePixel = 0;
		    Size = UDim2.new(1, 0, 1, 0);
		    ZIndex = 18;
		    BackgroundColor3 = Library.BackgroundColor;
		    Parent = SatVibMapInner;
		});
		
		local RainbowToggle = Library:Create('TextButton', {
		    AutoButtonColor = false;
		    Size = UDim2.new(0, 34, 0, 15);
		    Position = UDim2.new(0, 4, 0, 4);
		    BackgroundColor3 = Library.MainColor;
		    BorderSizePixel = 0;
		    Text = "AUTO";
		    TextSize = 9;
		    TextColor3 = Library.FontColor;
		    Font = Library.FontBold;
		    ZIndex = 25;
		    Parent = SatVibMapOuter;
		});

		Library:AddCorner(RainbowToggle, 4);
		Library:AddStroke(RainbowToggle, 'BorderColor');
		
		Library:Create('UIGradient', {
		    Color = ColorSequence.new({
		        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		        ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
		    });
		    Rotation = 90;
		    Parent = RainbowToggle;
		});
		
		Library:AddToRegistry(RainbowToggle, {
		    BackgroundColor3 = 'MainColor';
		    BorderColor3 = 'BorderColor';
		    TextColor3 = 'FontColor';
		});
		
		local SatVibMap = Library:Create('Frame', {
		    BorderSizePixel = 0;
		    Size = UDim2.new(1, 0, 1, 0);
		    ZIndex = 18;
		    BackgroundColor3 = Color3.fromRGB(255, 0, 0);
		    Parent = SatVibMapContainer;
		});

		Library:AddCorner(SatVibMap, 5);
		
		local SaturationGradient = Library:Create('UIGradient', {
		    Color = ColorSequence.new{
		        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 255, 255)),
		        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 0, 0))
		    };
		    Rotation = 0;
		    Parent = SatVibMap;
		});
		
		local ValueOverlay = Library:Create('Frame', {
		    BorderSizePixel = 0;
		    Size = UDim2.new(1, 0, 1, 0);
		    ZIndex = 19;
		    BackgroundColor3 = Color3.fromRGB(0, 0, 0);
		    Parent = SatVibMap;
		});

		Library:AddCorner(ValueOverlay, 5);
		
		local ValueGradient = Library:Create('UIGradient', {
		    Color = ColorSequence.new{
		        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 255, 255)),
		        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(0, 0, 0))
		    };
		    Rotation = 90;
		    Transparency = NumberSequence.new{
		        NumberSequenceKeypoint.new(0.0, 1),
		        NumberSequenceKeypoint.new(1.0, 0)
		    };
		    Parent = ValueOverlay;
		});
		
		local isRainbowMode = false;
		local rainbowConnection;
		local currentHue = 0;
		
		RainbowToggle.MouseButton1Click:Connect(function()
		    isRainbowMode = not isRainbowMode;
		    RainbowToggle.Text = isRainbowMode and "STOP" or "AUTO";
		    Library:Tween(RainbowToggle, { BackgroundColor3 = isRainbowMode and Library.AccentColor or Library.MainColor }, 0.25);
		    Library.RegistryMap[RainbowToggle].Properties.BackgroundColor3 = isRainbowMode and 'AccentColor' or 'MainColor';
		    
		    if isRainbowMode then
		        rainbowConnection = RenderStepped:Connect(function()
		            currentHue = currentHue + 0.005;
		            if currentHue > 1 then currentHue = 0 end;
		            
		            local newColor = Color3.fromHSV(currentHue, 1, 1);
		            SatVibMap.BackgroundColor3 = newColor;
		            SaturationGradient.Color = ColorSequence.new{
		                ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 255, 255)),
		                ColorSequenceKeypoint.new(1.0, newColor)
		            };
		            
		            ColorPicker.Hue = currentHue;
		            ColorPicker:Display();
		        end);
		    else
		        if rainbowConnection then
		            rainbowConnection:Disconnect();
		        end;
		    end;
		end);
		
		SatVibMap.InputBegan:Connect(function(Input)
		    if IsPress(Input) then
		        Library.CanDrag = false;

		        Library:TrackPointer(Input, function(PointerX, PointerY)
		            local MinX = SatVibMap.AbsolutePosition.X;
		            local MaxX = MinX + SatVibMap.AbsoluteSize.X;
		            local MouseX = math.clamp(PointerX, MinX, MaxX);

		            local MinY = SatVibMap.AbsolutePosition.Y;
		            local MaxY = MinY + SatVibMap.AbsoluteSize.Y;
		            local MouseY = math.clamp(PointerY, MinY, MaxY);

		            ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX);
		            ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY));
		            ColorPicker:Display();

		            if not isRainbowMode then
		                local newColor = Color3.fromHSV(ColorPicker.Hue, 1, 1);
		                SatVibMap.BackgroundColor3 = newColor;
		                SaturationGradient.Color = ColorSequence.new{
		                    ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 255, 255)),
		                    ColorSequenceKeypoint.new(1.0, newColor)
		                };
		            end;
		        end);

		        Library.CanDrag = true;
		        Library:AttemptSave();
		    end;
		end);

		local HueSelectorOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.new(0, 210, 0, 26);
			Size = UDim2.new(0, 14, 0, 200);
			ZIndex = 17;
			Parent = PickerFrameInner;
		});

		local HueSelectorInner = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(1, 1, 1);
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 18;
			Parent = HueSelectorOuter;
		});

		Library:AddCorner(HueSelectorInner, 4);

		local HueCursor = Library:Create('Frame', {
			BackgroundColor3 = Color3.new(1, 1, 1);
			AnchorPoint = Vector2.new(0.5, 0.5);
			BorderSizePixel = 0;
			Position = UDim2.new(0.5, 0, 0, 0);
			Size = UDim2.new(1, 4, 0, 4);
			ZIndex = 19;
			Parent = HueSelectorInner;
		});

		Library:AddCorner(HueCursor, 2);
		Library:AddStroke(HueCursor, Color3.new(0, 0, 0), 1, 0.3);

		local HueBoxOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.fromOffset(5, 230),
			Size = UDim2.new(0.5, -7, 0, 20),
			ZIndex = 18,
			Parent = PickerFrameInner;
		});

		local HueBoxInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 18,
			Parent = HueBoxOuter;
		});

		Library:AddCorner(HueBoxInner, 4);
		Library:AddStroke(HueBoxInner, 'BorderColor');

		Library:Create('UIGradient', {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
			});
			Rotation = 90;
			Parent = HueBoxInner;
		});

		local HueBox = Library:Create('TextBox', {
			BackgroundTransparency = 1;
			Position = UDim2.new(0, 5, 0, 0);
			Size = UDim2.new(1, -5, 1, 0);
			Font = Library.Font;
			PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
			PlaceholderText = 'Hex color',
			Text = '#FFFFFF',
			TextColor3 = Library.FontColor;
			TextSize = 13;
			TextStrokeTransparency = 0;
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 20,
			Parent = HueBoxInner;
		});

		Library:ApplyTextStroke(HueBox);

		local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
			Position = UDim2.new(0.5, 2, 0, 230),
			Size = UDim2.new(0.5, -7, 0, 20),
			Parent = PickerFrameInner
		});

		local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
			Text = '255, 255, 255',
			PlaceholderText = 'RGB color',
			TextColor3 = Library.FontColor
		});

		local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;
		
		if Info.Transparency then 
			TransparencyBoxOuter = Library:Create('Frame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Position = UDim2.fromOffset(5, 254);
				Size = UDim2.new(1, -10, 0, 13);
				ZIndex = 19;
				Parent = PickerFrameInner;
			});

			TransparencyBoxInner = Library:Create('Frame', {
				BackgroundColor3 = ColorPicker.Value;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 19;
				Parent = TransparencyBoxOuter;
			});

			Library:AddCorner(TransparencyBoxInner, 4);
			Library:AddStroke(TransparencyBoxInner, 'BorderColor');

			TransparencyCursor = Library:Create('Frame', {
				BackgroundColor3 = Color3.new(1, 1, 1);
				AnchorPoint = Vector2.new(0.5, 0.5);
				BorderSizePixel = 0;
				Position = UDim2.new(0, 0, 0.5, 0);
				Size = UDim2.new(0, 4, 1, 4);
				ZIndex = 21;
				Parent = TransparencyBoxInner;
			});

			Library:AddCorner(TransparencyCursor, 2);
			Library:AddStroke(TransparencyCursor, Color3.new(0, 0, 0), 1, 0.3);
		end;

		local DisplayLabel = Library:CreateLabel({
			Size = UDim2.new(1, -16, 0, 14);
			Position = UDim2.fromOffset(8, 7);
			Font = Library.FontBold;
			TextXAlignment = Enum.TextXAlignment.Left;
			TextSize = 13;
			Text = ColorPicker.Title,
			TextWrapped = false;
			ZIndex = 16;
			Parent = PickerFrameInner;
		});


		local ContextMenu = {}
		do
			ContextMenu.Options = {}
			ContextMenu.Container = Library:Create('Frame', {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 14,

				Visible = false,
				Parent = ScreenGui
			})

			ContextMenu.Inner = Library:Create('Frame', {
				BackgroundColor3 = Library.BackgroundColor;
				BorderSizePixel = 0;
				Size = UDim2.fromScale(1, 1);
				ZIndex = 15;
				Parent = ContextMenu.Container;
			});

			Library:AddCorner(ContextMenu.Inner, 6);
			Library:AddStroke(ContextMenu.Inner, 'BorderColor');

			Library:Create('UIListLayout', {
				Name = 'Layout',
				FillDirection = Enum.FillDirection.Vertical;
				SortOrder = Enum.SortOrder.LayoutOrder;
				Parent = ContextMenu.Inner;
			});

			Library:Create('UIPadding', {
				Name = 'Padding',
				PaddingLeft = UDim.new(0, 8),
				PaddingTop = UDim.new(0, 3),
				Parent = ContextMenu.Inner,
			});

			local function updateMenuPosition()
				ContextMenu.Container.Position = UDim2.fromOffset(
					(DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 4,
					DisplayFrame.AbsolutePosition.Y + 1
				)
			end

			local function updateMenuSize()
				local menuWidth = 60
				for i, label in next, ContextMenu.Inner:GetChildren() do
					if label:IsA('TextLabel') then
						menuWidth = math.max(menuWidth, label.TextBounds.X)
					end
				end

				ContextMenu.Container.Size = UDim2.fromOffset(
					menuWidth + 18,
					ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 8
				)
			end

			DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition)
			ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize)

			task.spawn(updateMenuPosition)
			task.spawn(updateMenuSize)

			Library:AddToRegistry(ContextMenu.Inner, {
				BackgroundColor3 = 'BackgroundColor';
				BorderColor3 = 'BorderColor';
			});

			function ContextMenu:Show()
				if Library.IsMobile then
					Library.CanDrag = false;
				end;

				Library:FadeFrame(self.Container, true, 0.12);
			end

			function ContextMenu:Hide()
				if Library.IsMobile then
					Library.CanDrag = true;
				end;
				
				Library:FadeFrame(self.Container, false, 0.1);
			end

			function ContextMenu:AddOption(Str, Callback)
				if type(Callback) ~= 'function' then
					Callback = function() end
				end

				local Button = Library:CreateLabel({
					Active = false;
					Size = UDim2.new(1, 0, 0, TouchSize(18));
					TextSize = 12;
					Text = Str;
					ZIndex = 16;
					Parent = self.Inner;
					TextXAlignment = Enum.TextXAlignment.Left,
				});

				Library:OnHighlight(Button, Button, 
					{ TextColor3 = 'AccentColor' },
					{ TextColor3 = 'FontColor' }
				);

				Library:OnTap(Button, function()
					Callback()
					ContextMenu:Hide()
				end)
			end

			ContextMenu:AddOption('Copy color', function()
				Library.ColorClipboard = ColorPicker.Value
				Library:Notify('Copied color!', 2)
			end)

			ContextMenu:AddOption('Paste color', function()
				if not Library.ColorClipboard then
					return Library:Notify('You have not copied a color!', 2)
				end
				ColorPicker:SetValueRGB(Library.ColorClipboard)
			end)


			ContextMenu:AddOption('Copy HEX', function()
				pcall(setclipboard, ColorPicker.Value:ToHex())
				Library:Notify('Copied hex code to clipboard!', 2)
			end)

			ContextMenu:AddOption('Copy RGB', function()
				pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '))
				Library:Notify('Copied RGB values to clipboard!', 2)
			end)

		end

		Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'BorderColor'; });
		Library:AddToRegistry(Highlight, { BackgroundColor3 = 'AccentColor'; });
		Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'BorderColor'; });

		Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'BorderColor'; });
		Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'BorderColor'; });
		Library:AddToRegistry(RgbBox, { TextColor3 = 'FontColor', });
		Library:AddToRegistry(HueBox, { TextColor3 = 'FontColor', });

		local SequenceTable = {};

		for Hue = 0, 1, 0.1 do
			table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)));
		end;

		local HueSelectorGradient = Library:Create('UIGradient', {
			Color = ColorSequence.new(SequenceTable);
			Rotation = 90;
			Parent = HueSelectorInner;
		});

		HueBox.FocusLost:Connect(function(enter)
			if enter then
				local success, result = pcall(Color3.fromHex, HueBox.Text)
				if success and typeof(result) == 'Color3' then
					ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
				end
			end

			ColorPicker:Display()
		end)

		RgbBox.FocusLost:Connect(function(enter)
			if enter then
				local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)')
				if r and g and b then
					ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
				end
			end

			ColorPicker:Display()
		end)

		function ColorPicker:Display()
			ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
			SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);

			Library:Create(DisplayFrame, {
				BackgroundColor3 = ColorPicker.Value;
				BackgroundTransparency = ColorPicker.Transparency;
				BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
			});

			if TransparencyBoxInner then
				TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
				TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0.5, 0);
			end;

			HueCursor.Position = UDim2.new(0.5, 0, ColorPicker.Hue, 0);
			DisplayStroke.Color = Library:GetDarkerColor(ColorPicker.Value);

			HueBox.Text = '#' .. ColorPicker.Value:ToHex()
			RgbBox.Text = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ')

			Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
			Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value);
		end;

		function ColorPicker:OnChanged(Func)
			ColorPicker.Changed = Library:ChainCallback(ColorPicker.Changed, Func);
			Func(ColorPicker.Value)
		end;

		if ParentObj.Addons then
			table.insert(ParentObj.Addons, ColorPicker)
		end

		function ColorPicker:Show()
			for Frame, Val in next, Library.OpenedFrames do
				if Frame.Name == 'Color' then
					Library:FadeFrame(Frame, false, 0.1);
					Library.OpenedFrames[Frame] = nil;
				end;
			end;

			Library:FadeFrame(PickerFrameOuter, true, 0.15);
			Library.OpenedFrames[PickerFrameOuter] = true;
		end;

		function ColorPicker:Hide()
			Library:FadeFrame(PickerFrameOuter, false, 0.12);
			Library.OpenedFrames[PickerFrameOuter] = nil;
		end;

		function ColorPicker:SetValue(HSV, Transparency)
			local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3]);

			ColorPicker.Transparency = Transparency or 0;
			ColorPicker:SetHSVFromRGB(Color);
			ColorPicker:Display();
		end;

		function ColorPicker:SetValueRGB(Color, Transparency)
			ColorPicker.Transparency = Transparency or 0;
			ColorPicker:SetHSVFromRGB(Color);
			ColorPicker:Display();
		end;

		-- (the saturation / value map handler lives next to the rainbow toggle above; a second copy here used to run it twice)

		HueSelectorInner.InputBegan:Connect(function(Input)
			if IsPress(Input) then
				Library.CanDrag = false;

				Library:TrackPointer(Input, function(PointerX, PointerY)
					local MinY = HueSelectorInner.AbsolutePosition.Y;
					local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y;
					local MouseY = math.clamp(PointerY, MinY, MaxY);

					ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY));
					ColorPicker:Display();
				end);

				Library.CanDrag = true;
				Library:AttemptSave();
			end;
		end);

		-- tap opens the picker; right-click (or long-press on phones) opens the copy / paste menu
		Library:OnTap(DisplayFrame, function(Input)
			if Library:MouseIsOverOpenedFrame(Input) then
				return;
			end;

			if PickerFrameOuter.Visible then
				ColorPicker:Hide()
			else
				ContextMenu:Hide()
				ColorPicker:Show()
			end;
		end);

		DisplayFrame.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
				ContextMenu:Show()
				ColorPicker:Hide()
			end
		end);

		Library:OnLongPress(DisplayFrame, function()
			ContextMenu:Show()
			ColorPicker:Hide()
		end);

		if TransparencyBoxInner then
			TransparencyBoxInner.InputBegan:Connect(function(Input)
				if IsPress(Input) then
					Library.CanDrag = false;

					Library:TrackPointer(Input, function(PointerX)
						local MinX = TransparencyBoxInner.AbsolutePosition.X;
						local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X;
						local MouseX = math.clamp(PointerX, MinX, MaxX);

						ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX));

						ColorPicker:Display();
					end);

					Library.CanDrag = true;
					Library:AttemptSave();
				end;
			end);
		end;

		Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
				local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;
				local PX, PY = Library:GetPointer(Input);

				if PX < AbsPos.X or PX > AbsPos.X + AbsSize.X
					or PY < (AbsPos.Y - 20 - 1) or PY > AbsPos.Y + AbsSize.Y then

					ColorPicker:Hide();
				end;

				if not Library:MouseIsOverFrame(ContextMenu.Container, Input) then
					ContextMenu:Hide()
				end
			end;

			if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
				if not Library:MouseIsOverFrame(ContextMenu.Container) and not Library:MouseIsOverFrame(DisplayFrame) then
					ContextMenu:Hide()
				end
			end
		end))

		ColorPicker:Display();
		ColorPicker.DisplayFrame = DisplayFrame

		Options[Idx] = ColorPicker;

		return self;
	end;

	function Funcs:AddKeyPicker(Idx, Info)
		local ParentObj = self;
		local ToggleLabel = self.TextLabel;
		local Container = self.Container;

		assert(Info.Default, 'AddKeyPicker: Missing default value.');

		local KeyPicker = {
			Value = Info.Default;
			Toggled = false;
			Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
			Type = 'KeyPicker';
			Callback = Info.Callback or function(Value) end;
			ChangedCallback = Info.ChangedCallback or function(New) end;
			SyncToggleState = Info.SyncToggleState or false;
		};

		if KeyPicker.SyncToggleState then
			Info.Modes = { 'Toggle' }
			Info.Mode = 'Toggle'
		end

		local PickOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(0, TouchSize(32), 0, TouchSize(15));
			ZIndex = 6;
			Parent = ToggleLabel;
		});

		local PickInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 7;
			Parent = PickOuter;
		});

		Library:AddCorner(PickInner, 4);
		local PickStroke = Library:AddStroke(PickInner, 'BorderColor');

		Library:AddToRegistry(PickInner, {
			BackgroundColor3 = 'BackgroundColor';
		});

		Library:OnHighlight(PickOuter, PickStroke,
			{ Color = 'AccentColor' },
			{ Color = 'BorderColor' }
		);

		local DisplayLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 1, 0);
			TextSize = 11;
			Text = Info.Default;
			TextWrapped = true;
			ZIndex = 8;
			Parent = PickInner;
		});

		local ModeSelectOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 6, ToggleLabel.AbsolutePosition.Y + 1);
			Size = UDim2.new(0, TouchSize(70), 0, TouchSize(18) * #(Info.Modes or { 1, 2, 3 }) + 6);
			Visible = false;
			ZIndex = 14;
			Parent = ScreenGui;
		});

		ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
			ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 6, ToggleLabel.AbsolutePosition.Y + 1);
		end);

		local ModeSelectInner = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 15;
			Parent = ModeSelectOuter;
		});

		Library:AddCorner(ModeSelectInner, 6);
		Library:AddStroke(ModeSelectInner, 'BorderColor');

		Library:AddToRegistry(ModeSelectInner, {
			BackgroundColor3 = 'BackgroundColor';
		});

		Library:Create('UIListLayout', {
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = ModeSelectInner;
		});

		Library:Create('UIPadding', {
			PaddingTop = UDim.new(0, 3);
			Parent = ModeSelectInner;
		});

		local ContainerLabel = Library:CreateLabel({
			TextXAlignment = Enum.TextXAlignment.Left;
			Size = UDim2.new(1, 0, 0, TouchSize(18));
			TextSize = 13;
			Visible = false;
			ZIndex = 110;
			Parent = Library.KeybindContainer;
		},  true);

		local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' };
		local ModeButtons = {};

		for Idx, Mode in next, Modes do
			local ModeButton = {};

			local Label = Library:CreateLabel({
				Active = false;
				Size = UDim2.new(1, 0, 0, TouchSize(18));
				TextSize = 12;
				Text = Mode;
				ZIndex = 16;
				Parent = ModeSelectInner;
			});

			function ModeButton:Select()
				for _, Button in next, ModeButtons do
					Button:Deselect();
				end;

				KeyPicker.Mode = Mode;

				Library:Tween(Label, { TextColor3 = Library.AccentColor }, 0.2);
				Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

				Library:FadeFrame(ModeSelectOuter, false);
			end;

			function ModeButton:Deselect()
				KeyPicker.Mode = nil;

				Library:Tween(Label, { TextColor3 = Library.FontColor }, 0.2);
				Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
			end;

			Library:OnTap(Label, function()
				ModeButton:Select();
				Library:AttemptSave();
			end);

			if Mode == KeyPicker.Mode then
				ModeButton:Select();
			end;

			ModeButtons[Mode] = ModeButton;
		end;

		function KeyPicker:Update()
			if Info.NoUI then
				return;
			end;

			local State = KeyPicker:GetState();

			ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);

			ContainerLabel.Visible = true;
			Library:Tween(ContainerLabel, { TextColor3 = State and Library.AccentColor or Library.DimFontColor }, 0.25);

			Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'DimFontColor';

			local YSize = 0
			local XSize = 0

			for _, Label in next, Library.KeybindContainer:GetChildren() do
				if Label:IsA('TextLabel') and Label.Visible then
					YSize = YSize + TouchSize(18);
					if (Label.TextBounds.X > XSize) then
						XSize = Label.TextBounds.X
					end
				end;
			end;

			Library:Tween(Library.KeybindFrame, { Size = UDim2.new(0, math.max(XSize + 20, 210), 0, YSize + 32) }, 0.3)
		end;

		function KeyPicker:GetState()
			if KeyPicker.Mode == 'Always' then
				return true;
			elseif KeyPicker.Mode == 'Hold' then
				if KeyPicker.Value == 'None' then
					return false;
				end

				local Key = KeyPicker.Value;

				if Key == 'MB1' or Key == 'MB2' then
					return Key == 'MB1' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
						or Key == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
				else
					return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]);
				end;
			else
				return KeyPicker.Toggled;
			end;
		end;

		function KeyPicker:SetValue(Data)
			local Key, Mode = Data[1], Data[2];
			DisplayLabel.Text = Key;
			KeyPicker.Value = Key;
			if ModeButtons[Mode] then ModeButtons[Mode]:Select(); end
			KeyPicker:Update();
		end;

		function KeyPicker:OnClick(Callback)
			KeyPicker.Clicked = Callback
		end

		function KeyPicker:OnChanged(Callback)
			KeyPicker.Changed = Library:ChainCallback(KeyPicker.Changed, Callback)
			Callback(KeyPicker.Value)
		end

		if ParentObj.Addons then
			table.insert(ParentObj.Addons, KeyPicker)
		end

		function KeyPicker:DoClick()
			if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
				ParentObj:SetValue(not ParentObj.Value)
			end

			Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
			Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
		end

		local Picking = false;

		PickOuter.InputBegan:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
				Picking = true;

				DisplayLabel.Text = '';
				Library:Tween(PickInner, { BackgroundColor3 = Library.BackgroundColor:Lerp(Library.AccentColor, 0.25) }, 0.25);

				local Break;
				local Text = '';

				task.spawn(function()
					while (not Break) do
						if Text == '...' then
							Text = '';
						end;

						Text = Text .. '.';
						DisplayLabel.Text = Text;

						task.wait(0.4);
					end;
				end);

				task.wait(0.2);

				local Event;
				Event = InputService.InputBegan:Connect(function(Input)
					local Key;

					if Input.UserInputType == Enum.UserInputType.Keyboard then
						Key = Input.KeyCode.Name;
					elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
						Key = 'MB1';
					elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
						Key = 'MB2';
					end;

					Break = true;
					Picking = false;

					Library:Tween(PickInner, { BackgroundColor3 = Library.BackgroundColor }, 0.35);
					DisplayLabel.Text = Key;
					KeyPicker.Value = Key;

					Library:SafeCallback(KeyPicker.ChangedCallback, Input.KeyCode or Input.UserInputType)
					Library:SafeCallback(KeyPicker.Changed, Input.KeyCode or Input.UserInputType)

					Library:AttemptSave();

					Event:Disconnect();
				end);
			elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
				Library:FadeFrame(ModeSelectOuter, true);
			end;
		end);

		-- phones have no keyboard to bind: a tap on the key box opens the mode menu (Always / Toggle / Hold)
		Library:OnTap(PickOuter, function(Input)
			if IsTouch(Input) and not Library:MouseIsOverOpenedFrame(Input) then
				Library:FadeFrame(ModeSelectOuter, not ModeSelectOuter.Visible);
			end;
		end);

		-- tapping a row in the Keybinds list flips it, so the list doubles as on-screen hotkeys on mobile
		Library:OnTap(ContainerLabel, function()
			if KeyPicker.Mode ~= 'Toggle' then
				return;
			end;

			KeyPicker.Toggled = not KeyPicker.Toggled;
			KeyPicker:DoClick();
			KeyPicker:Update();
		end);

		Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
			if KeyPicker.Value == "Unknown" then return end
		
			if (not Picking) and (not InputService:GetFocusedTextBox()) then
				if KeyPicker.Mode == 'Toggle' then
					local Key = KeyPicker.Value;

					if Key == 'MB1' or Key == 'MB2' then
						if Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1
						or Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2 then
							KeyPicker.Toggled = not KeyPicker.Toggled
							KeyPicker:DoClick()
						end;
					elseif Input.UserInputType == Enum.UserInputType.Keyboard then
						if Input.KeyCode.Name == Key then
							KeyPicker.Toggled = not KeyPicker.Toggled;
							KeyPicker:DoClick()
						end;
					end;
				end;

				KeyPicker:Update();
			end;

			if IsPress(Input) and ModeSelectOuter.Visible then
				-- the key box itself toggles the menu on tap, so don't count it as "outside"
				if not Library:MouseIsOverFrame(ModeSelectOuter, Input) and not Library:MouseIsOverFrame(PickOuter, Input) then
					Library:FadeFrame(ModeSelectOuter, false, 0.1);
				end;
			end;
		end))

		Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
			if (not Picking) then
				KeyPicker:Update();
			end;
		end))

		KeyPicker:Update();
		KeyPicker.DisplayFrame = PickOuter

		Options[Idx] = KeyPicker;

		return self;
	end;

	BaseAddons.__index = Funcs;
	BaseAddons.__namecall = function(Table, Key, ...)
		return Funcs[Key](...);
	end;
end;

local BaseGroupbox = {};

do
	local Funcs = {};

	function Funcs:AddBlank(Size)
		local Groupbox = self;
		local Container = Groupbox.Container;

		Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(1, 0, 0, Size);
			ZIndex = 1;
			Parent = Container;
		});
	end;

    function Funcs:AddLabel(Text, DoesWrap)
        local Label = {};
     
        local Groupbox = self;
        local Container = Groupbox.Container;
     
        local LabelContainer = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, -4, 0, 15);
            ZIndex = 5;
            Parent = Container;
        });
     
        local TextLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 13;
            Text = Text;
            TextWrapped = DoesWrap or false,
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = LabelContainer;
        });
     
        local Highlight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = 0.9;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 0, 1, 0);
            ZIndex = 4;
            Parent = LabelContainer;
        });
     
        Library:AddCorner(Highlight, 4);
        Library:AddToRegistry(Highlight, {
            BackgroundColor3 = 'AccentColor';
        });
     
        if DoesWrap then
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 13, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            LabelContainer.Size = UDim2.new(1, -4, 0, Y)
            TextLabel.Size = UDim2.new(1, 0, 1, 0)
        else
            Library:Create('UIListLayout', {
                Padding = UDim.new(0, 4);
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Right;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TextLabel;
            });
        end
     
        LabelContainer.MouseEnter:Connect(function()
            if Label._highlightTween then
                Label._highlightTween:Cancel()
            end
            Label._highlightTween = TweenService:Create(Highlight, 
                TweenInfo.new(0.35 * Library.AnimationSpeed, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Size = UDim2.new(1, 0, 1, 0);
                BackgroundTransparency = 0.95;
            });
            Label._highlightTween:Play();
        end)
     
        LabelContainer.MouseLeave:Connect(function()
            if Label._highlightTween then
                Label._highlightTween:Cancel()
            end
            Label._highlightTween = TweenService:Create(Highlight, 
                TweenInfo.new(0.35 * Library.AnimationSpeed, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 0, 1, 0);
                BackgroundTransparency = 0.9;
            });
            Label._highlightTween:Play();
        end)
     
        Label.TextLabel = TextLabel;
        Label.Container = Container;
     
        function Label:SetText(Text)
            TextLabel.Text = Text
     
            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, 13, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                LabelContainer.Size = UDim2.new(1, -4, 0, Y)
            end
     
            Groupbox:Resize();
        end
     
        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end
     
        Groupbox:AddBlank(5);
        Groupbox:Resize();
     
        return Label;
     end;

	 function Funcs:AddButton(...)
		local Button = {};
		local function ProcessButtonParams(Class, Obj, ...)
			local Props = select(1, ...)
			if type(Props) == 'table' then
				Obj.Text = Props.Text
				Obj.Func = Props.Func
				Obj.DoubleClick = Props.DoubleClick
				Obj.Tooltip = Props.Tooltip
			else
				Obj.Text = select(1, ...)
				Obj.Func = select(2, ...)
			end
	
			assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
		end
	
		ProcessButtonParams('Button', Button, ...)
	
		local Groupbox = self;
		local Container = Groupbox.Container;
		local function CreateBaseButton(Button)
			local Outer = Library:Create('Frame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Size = UDim2.new(1, -4, 0, TouchSize(22));
				ZIndex = 5;
			});

			local Inner = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5);
				BackgroundColor3 = Library.MainColor;
				BorderSizePixel = 0;
				ClipsDescendants = true;
				Position = UDim2.fromScale(0.5, 0.5);
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 6;
				Parent = Outer;
			});

			Library:AddCorner(Inner, 5);
			local Stroke = Library:AddStroke(Inner, 'BorderColor');
			local PressScale = Library:Create('UIScale', { Parent = Inner; });

			local HighlightOverlay = Library:Create('Frame', {
				BackgroundColor3 = Library.AccentColor;
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 7;
				Parent = Inner;
			});

			Library:AddCorner(HighlightOverlay, 5);

			local Label = Library:CreateLabel({
				Size = UDim2.new(1, 0, 1, 0);
				TextSize = 13;
				Text = Button.Text;
				ZIndex = 9;
				Parent = Inner;
			});

			Library:AddSheen(Inner, 0.14);

			Library:AddToRegistry(Inner, {
				BackgroundColor3 = 'MainColor';
			});

			Library:AddToRegistry(HighlightOverlay, {
				BackgroundColor3 = 'AccentColor';
			});

			Outer.MouseEnter:Connect(function()
				Library:Tween(Stroke, { Color = Library.AccentColor }, 0.2)
				Library.RegistryMap[Stroke].Properties.Color = 'AccentColor'
				Library:Tween(HighlightOverlay, { BackgroundTransparency = 0.88 }, 0.25)
			end)

			Outer.MouseLeave:Connect(function()
				Library:Tween(Stroke, { Color = Library.BorderColor }, 0.35)
				Library.RegistryMap[Stroke].Properties.Color = 'BorderColor'
				Library:Tween(HighlightOverlay, { BackgroundTransparency = 1 }, 0.35)
			end)

			Button.PressScale = PressScale


			return Outer, Inner, Label
		end
	
		local function InitEvents(Button)
			local function WaitForEvent(event, timeout, validator)
				local bindable = Instance.new('BindableEvent')
				local connection = event:Once(function(...)
	
					if type(validator) == 'function' and validator(...) then
						bindable:Fire(true)
					else
						bindable:Fire(false)
					end
				end)
				task.delay(timeout, function()
					connection:disconnect()
					bindable:Fire(false)
				end)
				return bindable.Event:Wait()
			end
	
			local function ValidateClick(Input)
				if Library:MouseIsOverOpenedFrame(Input) then
					return false
				end
	
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					return true
				elseif Input.UserInputType == Enum.UserInputType.Touch then
					return true
				else
					return false
				end
			end
	
			Library:OnTap(Button.Outer, function(Input)
				if not ValidateClick(Input) then return end
				if Button.Locked then return end


				if Input.UserInputType == Enum.UserInputType.Touch then
					Library:Ripple(Button.Inner, Input.Position.X, Input.Position.Y)
				else
					Library:Ripple(Button.Inner, Mouse.X, Mouse.Y)
				end
				Library:Press(Button.PressScale)

				if Button.DoubleClick then
					Library:RemoveFromRegistry(Button.Label)
					Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

					Library:Tween(Button.Label, { TextColor3 = Library.AccentColor }, 0.2)
					Button.Label.Text = 'Are you sure?'
					Button.Locked = true

					-- fingers are slower than a double-click: give touch users more time to confirm
					local clicked = WaitForEvent(Button.Outer.InputBegan, Library.IsMobile and 1.5 or 0.5, ValidateClick)

					Library:RemoveFromRegistry(Button.Label)
					Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

					Library:Tween(Button.Label, { TextColor3 = Library.FontColor }, 0.3)
					Button.Label.Text = Button.Text
					task.defer(rawset, Button, 'Locked', false)
	
					if clicked then
						Library:SafeCallback(Button.Func)
					end
	
					return
				end
	
				Library:SafeCallback(Button.Func);
			end)
		end
	
		Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
		Button.Outer.Parent = Container
	
		InitEvents(Button)
	
		function Button:AddTooltip(tooltip)
			if type(tooltip) == 'string' then
				Library:AddToolTip(tooltip, self.Outer)
			end
			return self
		end
	
	
		function Button:AddButton(...)
			local SubButton = {}
	
			ProcessButtonParams('SubButton', SubButton, ...)
	
			self.Outer.Size = UDim2.new(0.5, -2, 0, TouchSize(22))
	
			SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)
	
			SubButton.Outer.Position = UDim2.new(1, 3, 0, 0)
			SubButton.Outer.Size = UDim2.new(1, -3, 1, 0)
			SubButton.Outer.Parent = self.Outer
	
			function SubButton:AddTooltip(tooltip)
				if type(tooltip) == 'string' then
					Library:AddToolTip(tooltip, self.Outer)
				end
				return SubButton
			end
	
			if type(SubButton.Tooltip) == 'string' then
				SubButton:AddTooltip(SubButton.Tooltip)
			end
	
			InitEvents(SubButton)
			return SubButton
		end
	
		if type(Button.Tooltip) == 'string' then
			Button:AddTooltip(Button.Tooltip)
		end
	
		Groupbox:AddBlank(5);
		Groupbox:Resize();
	
		return Button;
	end;

	function Funcs:AddDivider()
		local Groupbox = self;
		local Container = self.Container

		local Divider = {
			Type = 'Divider',
		}

		Groupbox:AddBlank(2);
		local DividerOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(1, -4, 0, 5);
			ZIndex = 5;
			Parent = Container;
		});

		-- hairline that fades out at both ends
		local DividerInner = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0, 0.5);
			BackgroundColor3 = Library.BorderColor;
			BorderSizePixel = 0;
			Position = UDim2.new(0, 0, 0.5, 0);
			Size = UDim2.new(1, 0, 0, 1);
			ZIndex = 6;
			Parent = DividerOuter;
		});

		Library:Create('UIGradient', {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.1, 0),
				NumberSequenceKeypoint.new(0.9, 0),
				NumberSequenceKeypoint.new(1, 1),
			});
			Parent = DividerInner;
		});

		Library:AddToRegistry(DividerInner, {
			BackgroundColor3 = 'BorderColor';
		});

		Groupbox:AddBlank(9);
		Groupbox:Resize();
	end

	-- Category heading inside a groupbox:   GENERAL ───────────────
	-- Use it to split one groupbox into clear groups instead of a long, flat list of toggles.
	function Funcs:AddSection(Text)
		local Groupbox = self;
		local Container = Groupbox.Container;

		-- breathing room above, except for the very first thing in the box
		local Existing = 0;
		for _, Element in next, Container:GetChildren() do
			if not Element:IsA('UIListLayout') then
				Existing = Existing + 1;
			end;
		end;
		if Existing > 1 then
			Groupbox:AddBlank(5);
		end;

		local Title = string.upper(tostring(Text));
		local Width = Library:GetTextBounds(Title, Library.FontBold, 10);

		local Holder = Library:Create('Frame', {
			BackgroundTransparency = 1; BorderSizePixel = 0; Size = UDim2.new(1, -4, 0, 16); ZIndex = 5; Parent = Container;
		});

		local Label = Library:CreateLabel({
			Font = Library.FontBold; Position = UDim2.new(0, 0, 0, 0); Size = UDim2.new(0, Width + 2, 1, 0);
			Text = Title; TextSize = 10; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 6; Parent = Holder;
		});
		Label.TextColor3 = Library.AccentColor;
		Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

		local Line = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0, 0.5); BackgroundColor3 = Library.BorderColor; BorderSizePixel = 0;
			Position = UDim2.new(0, Width + 10, 0.5, 0); Size = UDim2.new(1, -(Width + 10), 0, 1); ZIndex = 6; Parent = Holder;
		});
		Library:Create('UIGradient', {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) });
			Parent = Line;
		});
		Library:AddToRegistry(Line, { BackgroundColor3 = 'BorderColor'; });

		Groupbox:AddBlank(2);
		Groupbox:Resize();
	end;
	function Funcs:AddInput(Idx, Info)
		assert(Info.Text, 'AddInput: Missing `Text` string.')

		local Textbox = {
			Value = Info.Default or '';
			Numeric = Info.Numeric or false;
			Finished = Info.Finished or false;
			Type = 'Input';
			Callback = Info.Callback or function(Value) end;
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		local InputLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 0, 15);
			TextSize = 13;
			Text = Info.Text;
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 5;
			Parent = Container;
		});

		Groupbox:AddBlank(1);

		local TextBoxOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(1, -4, 0, TouchSize(22));
			ZIndex = 5;
			Parent = Container;
		});

		local TextBoxInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = TextBoxOuter;
		});

		Library:AddCorner(TextBoxInner, 5);
		local TextBoxStroke = Library:AddStroke(TextBoxInner, 'BorderColor');

		Library:AddToRegistry(TextBoxInner, {
			BackgroundColor3 = 'MainColor';
		});

		if type(Info.Tooltip) == 'string' then
			Library:AddToolTip(Info.Tooltip, TextBoxOuter)
		end

		Library:AddSheen(TextBoxInner, 0.1);

		local Container = Library:Create('Frame', {
			BackgroundTransparency = 1;
			ClipsDescendants = true;

			Position = UDim2.new(0, 5, 0, 0);
			Size = UDim2.new(1, -5, 1, 0);

			ZIndex = 7;
			Parent = TextBoxInner;
		})

		local Box = Library:Create('TextBox', {
			BackgroundTransparency = 1;

			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(5, 1),

			Font = Library.Font;
			PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
			PlaceholderText = Info.Placeholder or '';

			Text = Info.Default or '';
			TextColor3 = Library.FontColor;
			TextSize = 13;
			TextStrokeTransparency = 0;
			TextXAlignment = Enum.TextXAlignment.Left;

			ClearTextOnFocus = (typeof(Info.ClearTextOnFocus) ~= "boolean" and true or Info.ClearTextOnFocus);

			ZIndex = 7;
			Parent = Container;
		});

		Library:ApplyTextStroke(Box);

		-- hover glows the outline, focus locks it to the accent color
		local Hovering = false;

		local function RefreshStroke()
			local Focused = Box:IsFocused();
			local ColorIdx = (Focused or Hovering) and 'AccentColor' or 'BorderColor';

			Library.RegistryMap[TextBoxStroke].Properties.Color = ColorIdx;
			Library:Tween(TextBoxStroke, { Color = Library[ColorIdx] }, Focused and 0.2 or 0.3);
			Library:Tween(TextBoxInner, { BackgroundColor3 = Focused and Library.MainColor:Lerp(Library.AccentColor, 0.06) or Library.MainColor }, 0.3);
		end;

		TextBoxOuter.MouseEnter:Connect(function() Hovering = true; RefreshStroke(); end);
		TextBoxOuter.MouseLeave:Connect(function() Hovering = false; RefreshStroke(); end);
		Box.Focused:Connect(RefreshStroke);
		Box.FocusLost:Connect(RefreshStroke);

		function Textbox:SetValue(Text)
			if Info.MaxLength and #Text > Info.MaxLength then
				Text = Text:sub(1, Info.MaxLength);
			end;

			if Textbox.Numeric then
				if (not tonumber(Text)) and Text:len() > 0 then
					Text = Textbox.Value
				end
			end

			Textbox.Value = Text;
			Box.Text = Text;

			Library:SafeCallback(Textbox.Callback, Textbox.Value);
			Library:SafeCallback(Textbox.Changed, Textbox.Value);
		end;

		if Textbox.Finished then
			Box.FocusLost:Connect(function(enter)
				if not enter then return end

				Textbox:SetValue(Box.Text);
				Library:AttemptSave();
			end)
		else
			Box:GetPropertyChangedSignal('Text'):Connect(function()
				Textbox:SetValue(Box.Text);
				Library:AttemptSave();
			end);
		end

		-- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
		-- thank you nicemike40 :)

		local function Update()
			local PADDING = 2
			local reveal = Container.AbsoluteSize.X

			if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
				-- we aren't focused, or we fit so be normal
				Box.Position = UDim2.new(0, PADDING, 0, 0)
			else
				-- we are focused and don't fit, so adjust position
				local cursor = Box.CursorPosition
				if cursor ~= -1 then
					-- calculate pixel width of text from start to cursor
					local subtext = string.sub(Box.Text, 1, cursor-1)
					local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

					-- check if we're inside the box with the cursor
					local currentCursorPos = Box.Position.X.Offset + width

					-- adjust if necessary
					if currentCursorPos < PADDING then
						Box.Position = UDim2.fromOffset(PADDING-width, 0)
					elseif currentCursorPos > reveal - PADDING - 1 then
						Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
					end
				end
			end
		end

		task.spawn(Update)

		Box:GetPropertyChangedSignal('Text'):Connect(Update)
		Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
		Box.FocusLost:Connect(Update)
		Box.Focused:Connect(Update)

		Library:AddToRegistry(Box, {
			TextColor3 = 'FontColor';
		});

		function Textbox:OnChanged(Func)
			Textbox.Changed = Library:ChainCallback(Textbox.Changed, Func);
			Func(Textbox.Value);
		end;

		Groupbox:AddBlank(5);
		Groupbox:Resize();

		Options[Idx] = Textbox;

		return Textbox;
	end;

	function Funcs:AddToggle(Idx, Info)
		assert(Info.Text, 'AddInput: Missing `Text` string.')

		local Toggle = {
			Value = Info.Default or false;
			Type = 'Toggle';

			Callback = Info.Callback or function(Value) end;
			Addons = {},
			Risky = Info.Risky,
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		local ToggleOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(0, TouchSize(14), 0, TouchSize(14));
			ZIndex = 5;
			Parent = Container;
		});

		local ToggleInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = ToggleOuter;
		});

		Library:AddCorner(ToggleInner, 4);
		local ToggleStroke = Library:AddStroke(ToggleInner, Toggle.Value and 'AccentColor' or 'BorderColor');

		Library:AddToRegistry(ToggleInner, {
			BackgroundColor3 = 'MainColor';
		});

		-- accent fill that pops in from the center
		local Fill = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5);
			BackgroundColor3 = Library.AccentColor;
			BackgroundTransparency = Toggle.Value and 0 or 1;
			BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 0.5);
			Size = Toggle.Value and UDim2.fromScale(1, 1) or UDim2.fromScale(0, 0);
			ZIndex = 7;
			Parent = ToggleInner;
		});

		Library:AddCorner(Fill, 4);
		Library:AddSheen(Fill, 0.18);
		Library:AddToRegistry(Fill, {
			BackgroundColor3 = 'AccentColor';
		});

		-- small inner dot, gives the "checked" state some depth
		local Dot = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5);
			BackgroundColor3 = Color3.new(1, 1, 1);
			BackgroundTransparency = Toggle.Value and 0.15 or 1;
			BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 0.5);
			Size = Toggle.Value and UDim2.fromOffset(TouchSize(4), TouchSize(4)) or UDim2.fromOffset(0, 0);
			ZIndex = 8;
			Parent = ToggleInner;
		});

		Library:AddCorner(Dot, 2);

		local ToggleLabel = Library:CreateLabel({
			Size = UDim2.new(0, 216, 1, 0);
			Position = UDim2.new(1, 8, 0, 0);
			TextSize = 13;
			Text = Info.Text;
			TextXAlignment = Enum.TextXAlignment.Left;
			ZIndex = 6;
			Parent = ToggleInner;
		});

		Library:Create('UIListLayout', {
			Padding = UDim.new(0, 4);
			FillDirection = Enum.FillDirection.Horizontal;
			HorizontalAlignment = Enum.HorizontalAlignment.Right;
			VerticalAlignment = Enum.VerticalAlignment.Center;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = ToggleLabel;
		});

		local ToggleRegion = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(0, Library.IsMobile and 200 or 170, 1, 0);
			ZIndex = 8;
			Parent = ToggleOuter;
		});




		local function OffLabelColor()
			return Library.FontColor:Lerp(Library.DimFontColor, 0.55);
		end;

		local Hovering = false;

		local function OverAddon()
			for _, Addon in next, Toggle.Addons do
				if Library:MouseIsOverFrame(Addon.DisplayFrame) then return true end
			end
			return false
		end;

		local function RefreshVisuals(Instant)
			local On = Toggle.Value;
			local Hot = On or (Hovering and not OverAddon());
			local Time = Instant and 0 or nil;

			Library.RegistryMap[ToggleStroke].Properties.Color = Hot and 'AccentColor' or 'BorderColor';
			Library:Tween(ToggleStroke, { Color = Hot and Library.AccentColor or Library.BorderColor }, Time or 0.25);

			if On then
				Library:Tween(Fill, { Size = UDim2.fromScale(1, 1); BackgroundTransparency = 0; }, Time or 0.4, Enum.EasingStyle.Back);
				Library:Tween(Dot, { Size = UDim2.fromOffset(TouchSize(4), TouchSize(4)); BackgroundTransparency = 0.15; }, Time or 0.45, Enum.EasingStyle.Back);
			else
				Library:Tween(Fill, { Size = UDim2.fromScale(0, 0); BackgroundTransparency = 1; }, Time or 0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
				Library:Tween(Dot, { Size = UDim2.fromOffset(0, 0); BackgroundTransparency = 1; }, Time or 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			end;

			if not Toggle.Risky then
				local Bright = On or Hovering;
				Library.RegistryMap[ToggleLabel].Properties.TextColor3 = Bright and 'FontColor' or OffLabelColor;
				Library:Tween(ToggleLabel, { TextColor3 = Bright and Library.FontColor or OffLabelColor() }, Time or 0.3);
			end;
		end;

		ToggleRegion.MouseEnter:Connect(function() Hovering = true; RefreshVisuals(); end);
		ToggleRegion.MouseMoved:Connect(function() RefreshVisuals(); end);
		ToggleRegion.MouseLeave:Connect(function() Hovering = false; RefreshVisuals(); end);

		function Toggle:UpdateColors()
			Toggle:Display();
		end;

		if type(Info.Tooltip) == 'string' then
			Library:AddToolTip(Info.Tooltip, ToggleRegion)
		end

        function Toggle:Display()
            if IsKrampus then setthreadcaps(8) end
            RefreshVisuals();
        end;
		function Toggle:OnChanged(Func)
			Toggle.Changed = Library:ChainCallback(Toggle.Changed, Func);
			Func(Toggle.Value);
		end;

		function Toggle:SetValue(Bool)
			Bool = (not not Bool);

			Toggle.Value = Bool;
			Toggle:Display();

			for _, Addon in next, Toggle.Addons do
				if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
					Addon.Toggled = Bool
					Addon:Update()
				end
			end

			Library:SafeCallback(Toggle.Callback, Toggle.Value);
			Library:SafeCallback(Toggle.Changed, Toggle.Value);
			Library:UpdateDependencyBoxes();
		end;

		Library:OnTap(ToggleRegion, function(Input)
			if not Library:MouseIsOverOpenedFrame(Input) then
				for _, Addon in next, Toggle.Addons do
					if Library:MouseIsOverFrame(Addon.DisplayFrame, Input) then return end
				end
				Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
				Library:AttemptSave();
			end;
		end);

		if Toggle.Risky then
			Library:RemoveFromRegistry(ToggleLabel)
			ToggleLabel.TextColor3 = Library.RiskColor
			Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
		end

		Toggle:Display();
		Groupbox:AddBlank(Info.BlankSize or TouchSize(7));
		Groupbox:Resize();

		Toggle.TextLabel = ToggleLabel;
		Toggle.Container = Container;
		setmetatable(Toggle, BaseAddons);

		Toggles[Idx] = Toggle;

		Library:UpdateDependencyBoxes();

		return Toggle;
	end;

	function Funcs:AddSlider(Idx, Info)
		assert(Info.Default, 'AddSlider: Missing default value.');
		assert(Info.Text, 'AddSlider: Missing slider text.');
		assert(Info.Min, 'AddSlider: Missing minimum value.');
		assert(Info.Max, 'AddSlider: Missing maximum value.');
		assert(Info.Rounding, 'AddSlider: Missing rounding value.');

		local Slider = {
			Value = Info.Default;
			Min = Info.Min;
			Max = Info.Max;
			Rounding = Info.Rounding;
			MaxSize = 232;
			Type = 'Slider';
			Callback = Info.Callback or function(Value) end;
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		if not Info.Compact then
			Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 12);
				TextSize = 13;
				Text = Info.Text;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextYAlignment = Enum.TextYAlignment.Bottom;
				ZIndex = 5;
				Parent = Container;
			});

			Groupbox:AddBlank(4);
		end

		local SliderOuter = Library:Create('Frame', {
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(1, -4, 0, TouchSize(15));
			ZIndex = 5;
			Parent = Container;
		});

		SliderOuter:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
			Slider.MaxSize = SliderOuter.AbsoluteSize.X;
		end);

		local SliderInner = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 1, 0);
			ZIndex = 6;
			Parent = SliderOuter;
		});

		Library:AddCorner(SliderInner, 4);
		local SliderStroke = Library:AddStroke(SliderInner, 'BorderColor');

		Library:AddToRegistry(SliderInner, {
			BackgroundColor3 = 'MainColor';
		});

		local Fill = Library:Create('Frame', {
			BackgroundColor3 = Library.AccentColor;
			BackgroundTransparency = 0.15;
			BorderSizePixel = 0;
			Size = UDim2.new(0, 0, 1, 0);
			ZIndex = 7;
			Parent = SliderInner;
		});

		Library:AddCorner(Fill, 4);
		Library:AddSheen(Fill, 0.25);

		Library:AddToRegistry(Fill, {
			BackgroundColor3 = 'AccentColor';
		});

		-- thin bright edge at the end of the fill
		local Knob = Library:Create('Frame', {
			AnchorPoint = Vector2.new(1, 0.5);
			BackgroundColor3 = Color3.new(1, 1, 1);
			BackgroundTransparency = 0.6;
			BorderSizePixel = 0;
			Position = UDim2.new(1, -2, 0.5, 0);
			Size = UDim2.new(0, 2, 1, -6);
			ZIndex = 8;
			Parent = Fill;
		});

		Library:AddCorner(Knob, 1);

		local DisplayLabel = Library:CreateLabel({
			Size = UDim2.new(1, 0, 1, 0);
			Font = Library.FontMedium;
			TextSize = 12;
			Text = 'Infinite';
			ZIndex = 9;
			Parent = SliderInner;
		});

		local Hovering, Dragging = false, false;

		local function RefreshHighlight()
			local Hot = Hovering or Dragging;
			Library.RegistryMap[SliderStroke].Properties.Color = Hot and 'AccentColor' or 'BorderColor';
			Library:Tween(SliderStroke, { Color = Hot and Library.AccentColor or Library.BorderColor }, Hot and 0.2 or 0.35);
			Library:Tween(Fill, { BackgroundTransparency = Dragging and 0 or 0.15 }, 0.25);
			Library:Tween(Knob, { BackgroundTransparency = Dragging and 0.1 or 0.6 }, 0.25);
		end;

		SliderOuter.MouseEnter:Connect(function() Hovering = true; RefreshHighlight(); end);
		SliderOuter.MouseLeave:Connect(function() Hovering = false; RefreshHighlight(); end);

		if type(Info.Tooltip) == 'string' then
			Library:AddToolTip(Info.Tooltip, SliderOuter)
		end

		function Slider:UpdateColors()
			Fill.BackgroundColor3 = Library.AccentColor;
		end;

        function Slider:Display()
            local Suffix = Info.Suffix or '';

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
            elseif Info.HideMax then
                DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
            else
                DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
            end

            local X = Library:MapValue(Slider.Value, Slider.Min, Slider.Max, 0, 1);

            -- smooth glide toward the new value
            Library:Tween(Fill, { Size = UDim2.new(X, 0, 1, 0) }, 0.18);
            Knob.Visible = X > 0.02;
         end;
		function Slider:OnChanged(Func)
			Slider.Changed = Library:ChainCallback(Slider.Changed, Func);
			Func(Slider.Value);
		end;

		local function Round(Value)
			if Slider.Rounding == 0 then
				return math.floor(Value);
			end;

			return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
		end;

		function Slider:GetValueFromXScale(X)
			return Round(Library:MapValue(X, 0, 1, Slider.Min, Slider.Max));
		end;
		
		function Slider:SetMax(Value)
			assert(Value > Slider.Min, 'Max value cannot be less than the current min value.');
			
			Slider.Value = math.clamp(Slider.Value, Slider.Min, Value);
			Slider.Max = Value;
			Slider:Display();
		end;
		
		function Slider:SetMin(Value)
			assert(Value < Slider.Max, 'Min value cannot be greater than the current max value.');

			Slider.Value = math.clamp(Slider.Value, Value, Slider.Max);
			Slider.Min = Value;
			Slider:Display();
		end;

		function Slider:SetValue(Str)
			local Num = tonumber(Str);

			if (not Num) then
				return;
			end;

			Num = math.clamp(Num, Slider.Min, Slider.Max);

			Slider.Value = Num;
			Slider:Display();

			Library:SafeCallback(Slider.Callback, Slider.Value);
			Library:SafeCallback(Slider.Changed, Slider.Value);
		end;

		local function SetFromPointer(PointerX)
			local nXOffset = math.clamp(PointerX - SliderInner.AbsolutePosition.X, 0, Slider.MaxSize);
			local nXScale = Library:MapValue(nXOffset, 0, Slider.MaxSize, 0, 1);

			local nValue = Slider:GetValueFromXScale(nXScale);
			local OldValue = Slider.Value;
			Slider.Value = nValue;

			Slider:Display();

			if nValue ~= OldValue then
				Library:SafeCallback(Slider.Callback, Slider.Value);
				Library:SafeCallback(Slider.Changed, Slider.Value);
			end;
		end;

		-- On touch, wait until the finger shows a direction: sideways = drag the slider,
		-- up/down = the user is scrolling the page, so leave the value alone.
		local function WaitForHorizontalIntent(Input)
			local StartX, StartY = Input.Position.X, Input.Position.Y;

			while Input.UserInputState ~= Enum.UserInputState.End and Input.UserInputState ~= Enum.UserInputState.Cancel do
				local DX = math.abs(Input.Position.X - StartX);
				local DY = math.abs(Input.Position.Y - StartY);

				if DX > 6 or DY > 6 then
					return DX >= DY;
				end;

				RenderStepped:Wait();
			end;

			-- released without moving = a tap: jump to that spot
			return true;
		end;

		SliderInner.InputBegan:Connect(function(Input)
			if not IsPress(Input) or Library:MouseIsOverOpenedFrame(Input) then
				return;
			end;

			if IsTouch(Input) and not WaitForHorizontalIntent(Input) then
				return;
			end;

			Library.CanDrag = false;

			local Sides = {};
			if Library.Window and Library.ActiveTab and Library.Window.Tabs[Library.ActiveTab] then
				Sides = Library.Window.Tabs[Library.ActiveTab]:GetSides();
			end

			for _, Side in pairs(Sides) do
				if typeof(Side) == "Instance" and Side:IsA("ScrollingFrame") then
					Side.ScrollingEnabled = false;
				end;
			end;

			Dragging = true;
			RefreshHighlight();

			-- a tap that already ended still sets the value once
			SetFromPointer((Library:GetPointer(Input)));
			Library:TrackPointer(Input, SetFromPointer);

			Dragging = false;
			RefreshHighlight();

			Library.CanDrag = true;

			for _, Side in pairs(Sides) do
				if typeof(Side) == "Instance" and Side:IsA("ScrollingFrame") then
					Side.ScrollingEnabled = true;
				end;
			end;

			Library:AttemptSave();
		end);

		Slider:Display();
		Groupbox:AddBlank(Info.BlankSize or 6);
		Groupbox:Resize();

		Options[Idx] = Slider;

		return Slider;
	end;

    function Funcs:AddDropdown(Idx, Info)
        if Info.SpecialType == 'Player' then
            Info.Values = GetPlayersString();
            Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then
            Info.Values = GetTeamsString();
            Info.AllowNull = true;
        end;

        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

        if (not Info.Text) then
            Info.Compact = true;
        end;

        local Dropdown = {
            Values = Info.Values;
            Value = Info.Multi and {};
            Multi = Info.Multi;
            Type = 'Dropdown';
            SpecialType = Info.SpecialType;
            Callback = Info.Callback or function(Value) end;
            isOpen = false;
            isAnimating = false;
            SearchBox = nil;
            LastSearchText = "";
            LastScrollPosition = Vector2.new(0, 0);
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local RelativeOffset = 0;

        if not Info.Compact then
            local DropdownLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 12);
                TextSize = 13;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(4);
        end

        for _, Element in next, Container:GetChildren() do
            if not Element:IsA('UIListLayout') then
                RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
            end;
        end;

        local DropdownOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, -4, 0, TouchSize(22));
            ZIndex = 5;
            Parent = Container;
        });

        local DropdownInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DropdownOuter;
        });

        Library:AddCorner(DropdownInner, 5);
        local DropdownStroke = Library:AddStroke(DropdownInner, 'BorderColor');

        Library:AddToRegistry(DropdownInner, {
            BackgroundColor3 = 'MainColor';
        });

        Library:AddSheen(DropdownInner, 0.1);

        local DropdownArrow = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.new(1, -12, 0.5, 0);
            Size = UDim2.new(0, 14, 0, 14);
            Image = 'rbxassetid://6034818372';
            ImageColor3 = Library.DimFontColor;
            Rotation = 0;
            ZIndex = 8;
            Parent = DropdownInner;
        });

        Library:AddToRegistry(DropdownArrow, {
            ImageColor3 = 'DimFontColor';
        });

        local ItemList = Library:CreateLabel({
            Position = UDim2.new(0, 8, 0, 0);
            Size = UDim2.new(1, -30, 1, 0);
            TextSize = 13;
            Text = '--';
            TextXAlignment = Enum.TextXAlignment.Left;
            TextWrapped = true;
            TextTruncate = Enum.TextTruncate.AtEnd;
            ZIndex = 7;
            Parent = DropdownInner;
        });

        local Hovering = false;

        local function RefreshHighlight()
            local Hot = Hovering or Dropdown.isOpen;
            local ArrowIdx = Dropdown.isOpen and 'AccentColor' or 'DimFontColor';

            Library.RegistryMap[DropdownStroke].Properties.Color = Hot and 'AccentColor' or 'BorderColor';
            Library:Tween(DropdownStroke, { Color = Hot and Library.AccentColor or Library.BorderColor }, Hot and 0.2 or 0.35);

            Library.RegistryMap[DropdownArrow].Properties.ImageColor3 = ArrowIdx;
            Library:Tween(DropdownArrow, { ImageColor3 = Library[ArrowIdx] }, 0.3);
        end;

        DropdownOuter.MouseEnter:Connect(function() Hovering = true; RefreshHighlight(); end);
        DropdownOuter.MouseLeave:Connect(function() Hovering = false; RefreshHighlight(); end);

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, DropdownOuter)
        end

        local MAX_DROPDOWN_ITEMS = 8;
        local ITEM_HEIGHT = TouchSize(22);
        local SEARCH_HEIGHT = TouchSize(26);

        -- CanvasGroup so the whole list can fade as one piece while it unrolls
        local ListOuter = Library:CreateCanvas({
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 0, 0, 0);
            ZIndex = 20;
            Visible = false;
            Parent = ScreenGui;
        });

        Library:AddCorner(ListOuter, 6);

        local VisibleCount = #Dropdown.Values;

        local function GetTargetHeight()
            local Y = math.clamp(VisibleCount * ITEM_HEIGHT, 0, MAX_DROPDOWN_ITEMS * ITEM_HEIGHT) + 6;
            if Dropdown.SearchBox then
                Y = Y + SEARCH_HEIGHT;
            end
            return Y;
        end;

        local function RecalculateListPosition()
            local dropdownPos = DropdownOuter.AbsolutePosition;
            local dropdownSize = DropdownOuter.AbsoluteSize;
            local screenSize = workspace.CurrentCamera.ViewportSize;

            local yPos = dropdownPos.Y + dropdownSize.Y + 4;
            local listHeight = GetTargetHeight();

            if yPos + listHeight > screenSize.Y - 20 then
                yPos = dropdownPos.Y - listHeight - 4;
            end

            ListOuter.Position = UDim2.fromOffset(dropdownPos.X, yPos);
        end;

        local function RecalculateListSize()
            if Dropdown.isOpen then
                Library:Tween(ListOuter, { Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, GetTargetHeight()) }, 0.3);
            end;
        end;

        RecalculateListPosition();

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);
        DropdownOuter:GetPropertyChangedSignal('AbsoluteSize'):Connect(RecalculateListSize);
        workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(RecalculateListPosition);

        local ListInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(1, 1);
            Size = UDim2.new(1, -2, 1, -2);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddCorner(ListInner, 5);
        Library:AddStroke(ListInner, 'BorderColor');

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
        });

        local Scrolling = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            CanvasSize = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, -4, 1, -4);
            Position = UDim2.new(0, 2, 0, 2);
            ZIndex = 21;
            Parent = ListInner;
            ScrollBarThickness = 3;
            VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar;
            ScrollingDirection = Enum.ScrollingDirection.Y;
            ElasticBehavior = Enum.ElasticBehavior.Never;

            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',

            ScrollBarImageColor3 = Library.AccentColor,
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'AccentColor'
        })

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 0);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Scrolling;
        });

        function Dropdown:CreateSearchBox()
            if Dropdown.SearchBox then return end

            Dropdown.SearchBox = Library:Create('TextBox', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, -8, 0, SEARCH_HEIGHT - 6);
                Position = UDim2.new(0, 4, 0, 4);
                Font = Library.Font;
                PlaceholderText = 'Search...';
                PlaceholderColor3 = Library.DimFontColor;
                Text = Dropdown.LastSearchText or '';
                TextColor3 = Library.FontColor;
                TextSize = 12;
                TextXAlignment = Enum.TextXAlignment.Left;
                ClearTextOnFocus = false;
                ZIndex = 22;
                Parent = ListInner;
            });

            Library:AddCorner(Dropdown.SearchBox, 4);
            local SearchStroke = Library:AddStroke(Dropdown.SearchBox, 'BorderColor');

            Library:Create('UIPadding', {
                PaddingLeft = UDim.new(0, 7);
                Parent = Dropdown.SearchBox;
            });

            Library:AddToRegistry(Dropdown.SearchBox, {
                BackgroundColor3 = 'BackgroundColor';
                TextColor3 = 'FontColor';
                PlaceholderColor3 = 'DimFontColor';
            });

            Dropdown.SearchBox.Focused:Connect(function()
                Library.RegistryMap[SearchStroke].Properties.Color = 'AccentColor';
                Library:Tween(SearchStroke, { Color = Library.AccentColor }, 0.2);
            end);

            Dropdown.SearchBox.FocusLost:Connect(function()
                Library.RegistryMap[SearchStroke].Properties.Color = 'BorderColor';
                Library:Tween(SearchStroke, { Color = Library.BorderColor }, 0.3);
            end);

            Dropdown.SearchBox:GetPropertyChangedSignal('Text'):Connect(function()
                Dropdown.LastSearchText = Dropdown.SearchBox.Text;
                Dropdown:BuildDropdownList(Dropdown.SearchBox.Text);
            end)

            Scrolling.Position = UDim2.new(0, 2, 0, SEARCH_HEIGHT + 2);
            Scrolling.Size = UDim2.new(1, -4, 1, -(SEARCH_HEIGHT + 4));
        end

        function Dropdown:RemoveSearchBox()
            if Dropdown.SearchBox then
                Dropdown.SearchBox:Destroy();
                Dropdown.SearchBox = nil;
                Scrolling.Position = UDim2.new(0, 2, 0, 2);
                Scrolling.Size = UDim2.new(1, -4, 1, -4);
            end
        end

        function Dropdown:Display()
            local Values = Dropdown.Values;
            local Str = '';

            if Info.Multi then
                for Idx, Value in next, Values do
                    if Dropdown.Value[Value] then
                        Str = Str .. Value .. ', ';
                    end;
                end;

                Str = Str:sub(1, #Str - 2);
            else
                Str = Dropdown.Value or '';
            end;

            ItemList.Text = (Str == '' and '--' or Str);
        end;

        function Dropdown:GetActiveValues()
            if Info.Multi then
                local T = {};

                for Value, Bool in next, Dropdown.Value do
                    table.insert(T, Value);
                end;

                return T;
            else
                return Dropdown.Value and 1 or 0;
            end;
        end;

        local ItemLabels = {};

        function Dropdown:BuildDropdownList(searchTerm)
            Dropdown.LastScrollPosition = Scrolling.CanvasPosition;

            local Values = Dropdown.Values;
            local Buttons = {};
            ItemLabels = {};

            for _, Element in next, Scrolling:GetChildren() do
                if not Element:IsA('UIListLayout') then
                    Element:Destroy();
                end;
            end;

            local Count = 0;
            for Idx, Value in next, Values do
                if searchTerm and searchTerm ~= '' then
                    if not string.find(string.lower(Value), string.lower(searchTerm), 1, true) then
                        continue;
                    end
                end

                local Table = {};

                Count = Count + 1;

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.AccentColor;
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    LayoutOrder = Count;
                    Size = UDim2.new(1, 0, 0, ITEM_HEIGHT);
                    ZIndex = 23;
                    Active = true;
                    Parent = Scrolling;
                });

                Library:AddCorner(Button, 4);

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'AccentColor';
                });

                local SelectBar = Library:Create('Frame', {
                    AnchorPoint = Vector2.new(0, 0.5);
                    BackgroundColor3 = Library.AccentColor;
                    BorderSizePixel = 0;
                    Position = UDim2.new(0, 3, 0.5, 0);
                    Size = UDim2.new(0, 2, 0, 0);
                    ZIndex = 24;
                    Parent = Button;
                });

                Library:AddCorner(SelectBar, 1);

                Library:AddToRegistry(SelectBar, {
                    BackgroundColor3 = 'AccentColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, -16, 1, 0);
                    Position = UDim2.new(0, 9, 0, 0);
                    TextSize = 13;
                    Text = Value;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    TextTruncate = Enum.TextTruncate.AtEnd;
                    ZIndex = 25;
                    Parent = Button;
                });

                local ItemHovering = false;
                local Selected;

                if Info.Multi then
                    Selected = Dropdown.Value[Value];
                else
                    Selected = Dropdown.Value == Value;
                end;

                function Table:UpdateButton(Instant)
                    if Info.Multi then
                        Selected = Dropdown.Value[Value];
                    else
                        Selected = Dropdown.Value == Value;
                    end;

                    local Time = Instant and 0 or nil;

                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                    Library:Tween(ButtonLabel, {
                        TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                        Position = UDim2.new(0, Selected and 13 or 9, 0, 0);
                    }, Time or 0.28);
                    Library:Tween(SelectBar, { Size = UDim2.new(0, 2, 0, Selected and ITEM_HEIGHT - 10 or 0) }, Time or 0.32);
                    Library:Tween(Button, { BackgroundTransparency = ItemHovering and 0.86 or (Selected and 0.93 or 1) }, Time or 0.2);
                end;

                Button.MouseEnter:Connect(function()
                    ItemHovering = true;
                    Table:UpdateButton();
                end);

                Button.MouseLeave:Connect(function()
                    ItemHovering = false;
                    Table:UpdateButton();
                end);

                Library:OnTap(Button, function(Input)
                    do
                        local Try = not Selected;

                        if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                        else
                            if Info.Multi then
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value[Value] = true;
                                else
                                    Dropdown.Value[Value] = nil;
                                end;
                            else
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value = Value;
                                else
                                    Dropdown.Value = nil;
                                end;

                                for _, OtherButton in next, Buttons do
                                    OtherButton:UpdateButton();
                                end;
                            end;

                            Table:UpdateButton();
                            Dropdown:Display();

                            Library:UpdateDependencyBoxes();
                            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

                            Library:AttemptSave();

                            if not Info.Multi then
                                task.wait(0.12);
                                Dropdown:CloseDropdown();
                            end
                        end;
                    end;
                end);

                Table:UpdateButton(true);

                Buttons[Button] = Table;
                table.insert(ItemLabels, ButtonLabel);
            end;

            Dropdown:Display();

            Scrolling.CanvasSize = UDim2.fromOffset(0, Count * ITEM_HEIGHT);
            VisibleCount = Count;
            RecalculateListSize();

            task.defer(function()
                Scrolling.CanvasPosition = Dropdown.LastScrollPosition;
            end)
        end;

        function Dropdown:SetValues(NewValues)
            if NewValues then
                Dropdown.Values = NewValues;
            end;

            if #Dropdown.Values > 10 or Dropdown.SpecialType == 'Player' then
                Dropdown:CreateSearchBox();
            else
                Dropdown:RemoveSearchBox();
            end

            Dropdown:BuildDropdownList(Dropdown.LastSearchText);
        end;

        local StateToken = 0;

        function Dropdown:OpenDropdown()
            if Dropdown.isOpen then
                return;
            end

            if Library.IsMobile then
                Library.CanDrag = false;
            end;

            for _, OtherOption in pairs(Options) do
                if OtherOption.Type == 'Dropdown' and OtherOption ~= Dropdown then
                    OtherOption:CloseDropdown();
                end
            end

            if (#Dropdown.Values > 10 or Dropdown.SpecialType == 'Player') and not Dropdown.SearchBox then
                Dropdown:CreateSearchBox();
                Dropdown:BuildDropdownList(Dropdown.LastSearchText);
            end

            Dropdown.isOpen = true;
            StateToken = StateToken + 1;

            RecalculateListPosition();

            if not ListOuter.Visible then
                Library:SetNow(ListOuter, 'Size', UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, 0));
                Library:SetGroupTransparency(ListOuter, 1);
                ListOuter.Visible = true;
            end;

            -- unroll + fade in
            Library:Tween(ListOuter, { Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, GetTargetHeight()) }, 0.38);
            Library:SetGroupTransparency(ListOuter, 0, 0.28);
            Library:Tween(DropdownArrow, { Rotation = 180 }, 0.38);
            RefreshHighlight();

            if Dropdown.SearchBox then
                Dropdown.SearchBox.Text = Dropdown.LastSearchText or '';
                -- on phones this would pop the keyboard over the list every time it opens
                if not Library.IsMobile then
                    Dropdown.SearchBox:CaptureFocus();
                end;
            end

            -- items cascade in one after another
            for Index, Label in ipairs(ItemLabels) do
                if Index > MAX_DROPDOWN_ITEMS + 2 then
                    break;
                end;

                Label.TextTransparency = 1;
                TweenService:Create(Label,
                    TweenInfo.new(0.3 * Library.AnimationSpeed, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, (0.03 + Index * 0.028) * Library.AnimationSpeed),
                    { TextTransparency = 0 }
                ):Play();
            end;

            Library.OpenedFrames[ListOuter] = true;
        end;

        function Dropdown:CloseDropdown()
            if not Dropdown.isOpen then
                return;
            end

            if Library.IsMobile then
                Library.CanDrag = true;
            end;

            if Dropdown.SearchBox then
                Dropdown.SearchBox:ReleaseFocus();
            end

            Dropdown.isOpen = false;
            StateToken = StateToken + 1;
            local Token = StateToken;

            Library.OpenedFrames[ListOuter] = nil;

            Library:Tween(ListOuter, { Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, 0) }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
            Library:SetGroupTransparency(ListOuter, 1, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
            Library:Tween(DropdownArrow, { Rotation = 0 }, 0.32);
            RefreshHighlight();

            task.delay(0.25 * Library.AnimationSpeed, function()
                if StateToken == Token then
                    ListOuter.Visible = false;
                end;
            end);
        end;
        function Dropdown:OnChanged(Func)
            Dropdown.Changed = Library:ChainCallback(Dropdown.Changed, Func);
            Func(Dropdown.Value);
        end;

        function Dropdown:SetValue(Val)
            if Dropdown.Multi then
                local nTable = {};

                for Value, Bool in next, Val do
                    if table.find(Dropdown.Values, Value) then
                        nTable[Value] = true
                    end;
                end;

                Dropdown.Value = nTable;
            else
                if (not Val) then
                    Dropdown.Value = nil;
                elseif table.find(Dropdown.Values, Val) then
                    Dropdown.Value = Val;
                end;
            end;

            Dropdown:BuildDropdownList();

            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
        end;

        Library:OnTap(DropdownOuter, function(Input)
            if not Library:MouseIsOverOpenedFrame(Input) then
                if Dropdown.isOpen then
                    Dropdown:CloseDropdown();
                else
                    Dropdown:OpenDropdown();
                end;
            end;
        end);

        -- press outside the list (and outside the dropdown itself, which toggles on its own) closes it
        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if IsPress(Input) and Dropdown.isOpen then
                if not Library:MouseIsOverFrame(ListOuter, Input) and not Library:MouseIsOverFrame(DropdownOuter, Input) then
                    Dropdown:CloseDropdown();
                end;
            end;
        end));

        Dropdown:BuildDropdownList();
        Dropdown:Display();

        local Defaults = {}

        if type(Info.Default) == 'string' then
            local Idx = table.find(Dropdown.Values, Info.Default)
            if Idx then
                table.insert(Defaults, Idx)
            end
        elseif type(Info.Default) == 'table' then
            for _, Value in next, Info.Default do
                local Idx = table.find(Dropdown.Values, Value)
                if Idx then
                    table.insert(Defaults, Idx)
                end
            end
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
            table.insert(Defaults, Info.Default)
        end

        if next(Defaults) then
            for i = 1, #Defaults do
                local Index = Defaults[i]
                if Info.Multi then
                    Dropdown.Value[Dropdown.Values[Index]] = true
                else
                    Dropdown.Value = Dropdown.Values[Index];
                end

                if (not Info.Multi) then break end
            end

           if Info.Multi or #Dropdown.Values > 10 or Dropdown.SpecialType == 'Player' then
				Dropdown:CreateSearchBox();
			end

            Dropdown:BuildDropdownList();
            Dropdown:Display();
        end

        Dropdown.DisplayFrame = DropdownOuter;

        Groupbox:AddBlank(Info.BlankSize or 5);
        Groupbox:Resize();

        Options[Idx] = Dropdown;

        return Dropdown;
    end;

	-- Grid of theme preview cards (used by ThemeManager).
	-- Info.Themes = { { Name = 'Tokyo'; Subtitle = 'Indigo night'; Colors = { BackgroundColor, MainColor, AccentColor, OutlineColor, FontColor } }, ... }
	-- Optional: Default, Callback, Columns (2), CardHeight (100), OnHover(Name), OnHoverEnd(Name)
	function Funcs:AddThemeGrid(Idx, Info)
		assert(type(Info.Themes) == 'table', 'AddThemeGrid: Missing `Themes` table.');

		local Groupbox = self;
		local Container = Groupbox.Container;

		local Columns = Info.Columns or 2;
		local CardHeight = Info.CardHeight or 100;
		local Gap = 6;

		local Grid = {
			Value = Info.Default;
			Themes = Info.Themes;
			Type = 'ThemeGrid';
			Callback = Info.Callback or function(Value) end;
		};

		local Holder = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(1, -4, 0, 0);
			ZIndex = 5;
			Parent = Container;
		});

		Library:Create('UIGridLayout', {
			CellPadding = UDim2.fromOffset(Gap, Gap);
			CellSize = UDim2.new(1 / Columns, -Gap * (Columns - 1) / Columns, 0, CardHeight);
			FillDirection = Enum.FillDirection.Horizontal;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = Holder;
		});

		local Cards = {};

		local function Bit(Parent, Color, Transparency, Props)
			local Frame = Library:Create('Frame', {
				BackgroundColor3 = Color;
				BackgroundTransparency = Transparency or 0;
				BorderSizePixel = 0;
				Parent = Parent;
			});
			local Radius = Props.Radius or 2;
			Props.Radius = nil;
			Library:Create(Frame, Props);
			Library:AddCorner(Frame, Radius);
			return Frame;
		end;

		local function BuildCard(Theme, Order)
			local C = Theme.Colors;
			local Card = { Name = Theme.Name; Selected = false; };

			local Cell = Library:Create('Frame', {
				BackgroundTransparency = 1;
				LayoutOrder = Order;
				ZIndex = 5;
				Parent = Holder;
			});

			local Body = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5);
				BackgroundColor3 = Library.BackgroundColor;
				BorderSizePixel = 0;
				ClipsDescendants = true;
				Position = UDim2.fromScale(0.5, 0.5);
				Size = UDim2.fromScale(1, 1);
				ZIndex = 6;
				Parent = Cell;
			});

			Library:AddCorner(Body, 7);
			local Stroke = Library:AddStroke(Body, 'BorderColor');
			local Scale = Library:Create('UIScale', { Parent = Body; });

			Library:AddToRegistry(Body, { BackgroundColor3 = 'BackgroundColor'; });

			-- miniature window painted in the theme's own colors
			local Preview = Library:Create('Frame', {
				BackgroundColor3 = C.BackgroundColor;
				BorderSizePixel = 0;
				ClipsDescendants = true;
				Position = UDim2.fromOffset(5, 5);
				Size = UDim2.new(1, -10, 0, CardHeight - 42);
				ZIndex = 7;
				Parent = Body;
			});

			Library:AddCorner(Preview, 5);
			Library:AddStroke(Preview, C.OutlineColor);

			Bit(Preview, C.AccentColor, 0, { Position = UDim2.fromOffset(6, 4); Size = UDim2.fromOffset(4, 4); ZIndex = 8; });
			Bit(Preview, C.FontColor, 0.55, { Position = UDim2.fromOffset(14, 5); Size = UDim2.fromOffset(22, 2); ZIndex = 8; });

			local Panel = Bit(Preview, C.MainColor, 0, {
				Position = UDim2.fromOffset(5, 12);
				Size = UDim2.new(1, -10, 1, -17);
				ZIndex = 8;
				Radius = 3;
			});

			-- row 1: label + toggle pill
			Bit(Panel, C.FontColor, 0.5, { AnchorPoint = Vector2.new(0, 0.5); Position = UDim2.new(0, 6, 0.2, 0); Size = UDim2.new(0.32, 0, 0, 2); ZIndex = 9; });
			local Pill = Bit(Panel, C.AccentColor, 0, { AnchorPoint = Vector2.new(1, 0.5); Position = UDim2.new(1, -6, 0.2, 0); Size = UDim2.fromOffset(13, 6); ZIndex = 9; Radius = 3; });
			Bit(Pill, C.FontColor, 0, { AnchorPoint = Vector2.new(1, 0.5); Position = UDim2.new(1, -1, 0.5, 0); Size = UDim2.fromOffset(4, 4); ZIndex = 10; });

			-- row 2: label + slider
			Bit(Panel, C.FontColor, 0.5, { AnchorPoint = Vector2.new(0, 0.5); Position = UDim2.new(0, 6, 0.5, 0); Size = UDim2.new(0.22, 0, 0, 2); ZIndex = 9; });
			local Track = Bit(Panel, C.OutlineColor, 0, { AnchorPoint = Vector2.new(1, 0.5); Position = UDim2.new(1, -6, 0.5, 0); Size = UDim2.new(0.45, 0, 0, 3); ZIndex = 9; });
			Bit(Track, C.AccentColor, 0, { Size = UDim2.new(0.6, 0, 1, 0); ZIndex = 10; });

			-- row 3: label + accent chip
			Bit(Panel, C.FontColor, 0.5, { AnchorPoint = Vector2.new(0, 0.5); Position = UDim2.new(0, 6, 0.8, 0); Size = UDim2.new(0.4, 0, 0, 2); ZIndex = 9; });
			Bit(Panel, C.AccentColor, 0.35, { AnchorPoint = Vector2.new(1, 0.5); Position = UDim2.new(1, -6, 0.8, 0); Size = UDim2.fromOffset(16, 5); ZIndex = 9; });

			-- check badge in the theme's accent
			local Badge = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5);
				BackgroundColor3 = C.AccentColor;
				BorderSizePixel = 0;
				Position = UDim2.new(1, -13, 0, 13);
				Size = UDim2.fromOffset(16, 16);
				ZIndex = 12;
				Parent = Body;
			});

			Library:AddCorner(Badge, 8);
			Library:AddStroke(Badge, C.BackgroundColor, 2);
			local BadgeScale = Library:Create('UIScale', { Scale = 0; Parent = Badge; });

			Library:Create('TextLabel', {
				BackgroundTransparency = 1;
				Font = Library.FontBold;
				Size = UDim2.fromScale(1, 1);
				Text = '✓';
				TextColor3 = C.BackgroundColor;
				TextSize = 11;
				ZIndex = 13;
				Parent = Badge;
			});

			local NameLabel = Library:CreateLabel({
				Position = UDim2.new(0, 8, 1, -34);
				Size = UDim2.new(1, -16, 0, 14);
				Font = Library.FontBold;
				Text = Theme.Name;
				TextSize = 12;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextTruncate = Enum.TextTruncate.AtEnd;
				ZIndex = 8;
				Parent = Body;
			});

			local SubLabel = Library:CreateLabel({
				Position = UDim2.new(0, 8, 1, -19);
				Size = UDim2.new(1, -16, 0, 12);
				Text = Theme.Subtitle or '';
				TextSize = 11;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextTruncate = Enum.TextTruncate.AtEnd;
				ZIndex = 8;
				Parent = Body;
			});

			SubLabel.TextColor3 = Library.DimFontColor;
			Library.RegistryMap[SubLabel].Properties.TextColor3 = 'DimFontColor';

			-- LIVE = the theme comes with an animated scene
			if Theme.Animated then
				local Live = Library:Create('Frame', {
					AnchorPoint = Vector2.new(1, 0); BackgroundColor3 = Library.AccentColor; BackgroundTransparency = 0.8; BorderSizePixel = 0;
					Position = UDim2.new(1, -8, 1, -33); Size = UDim2.fromOffset(34, 13); ZIndex = 9; Parent = Body;
				});
				Library:AddCorner(Live, 6);
				Library:AddStroke(Live, 'AccentColor');
				Library:AddToRegistry(Live, { BackgroundColor3 = 'AccentColor'; });

				local LiveText = Library:CreateLabel({ Font = Library.FontBold; Size = UDim2.fromScale(1, 1); Text = 'LIVE'; TextSize = 9; ZIndex = 10; Parent = Live; });
				LiveText.TextColor3 = Library.AccentColor;
				Library.RegistryMap[LiveText].Properties.TextColor3 = 'AccentColor';

				NameLabel.Size = UDim2.new(1, -52, 0, 14);
			end;


			local Hovering = false;

			local function Refresh(Instant)
				local Time = Instant and 0 or nil;
				local StrokeIdx = Card.Selected and 'AccentColor' or 'BorderColor';

				Library.RegistryMap[Stroke].Properties.Color = StrokeIdx;
				Library:Tween(Stroke, {
					Color = (Hovering and not Card.Selected) and Library.BorderColor:Lerp(Library.AccentColor, 0.5) or Library[StrokeIdx];
					Thickness = Card.Selected and 1.5 or 1;
				}, Time or 0.3);

				Library:Tween(Scale, { Scale = Hovering and 1.03 or 1 }, Time or 0.35);

				if Card.Selected then
					Library:Tween(BadgeScale, { Scale = 1 }, Time or 0.45, Enum.EasingStyle.Back);
				else
					Library:Tween(BadgeScale, { Scale = 0 }, Time or 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
				end;
			end;

			function Card:SetSelected(On, Instant)
				Card.Selected = On;
				Refresh(Instant);
			end;

			Cell.MouseEnter:Connect(function()
				Hovering = true;
				Refresh();
				if Info.OnHover then Library:SafeCallback(Info.OnHover, Theme.Name) end;
			end);

			Cell.MouseLeave:Connect(function()
				Hovering = false;
				Refresh();
				if Info.OnHoverEnd then Library:SafeCallback(Info.OnHoverEnd, Theme.Name) end;
			end);

			Library:OnTap(Cell, function(Input)
				if not Library:MouseIsOverOpenedFrame(Input) then
					if Input.UserInputType == Enum.UserInputType.Touch then
						Library:Ripple(Body, Input.Position.X, Input.Position.Y);
					else
						Library:Ripple(Body, Mouse.X, Mouse.Y);
					end;


					Grid:SetValue(Theme.Name);
					Library:AttemptSave();
				end;
			end);

			Card.Cell = Cell;
			Refresh(true);

			return Card;
		end;

		function Grid:SetThemes(Themes)
			for _, Card in next, Cards do
				Card.Cell:Destroy();
			end;

			Cards = {};
			Grid.Themes = Themes;

			for Order, Theme in ipairs(Themes) do
				local Card = BuildCard(Theme, Order);
				Card:SetSelected(Theme.Name == Grid.Value, true);
				table.insert(Cards, Card);
			end;

			local Rows = math.ceil(#Themes / Columns);
			Holder.Size = UDim2.new(1, -4, 0, math.max(Rows * CardHeight + (Rows - 1) * Gap, 0));
			Groupbox:Resize();
		end;

		function Grid:SetValue(Name)

			Grid.Value = Name;

			for _, Card in next, Cards do
				Card:SetSelected(Card.Name == Name);
			end;

			Library:SafeCallback(Grid.Callback, Grid.Value);
			Library:SafeCallback(Grid.Changed, Grid.Value);
		end;

		function Grid:OnChanged(Func)
			Grid.Changed = Library:ChainCallback(Grid.Changed, Func);
			Func(Grid.Value);
		end;

		if Grid.Value == nil and Info.Themes[1] then
			Grid.Value = Info.Themes[1].Name;
		end;

		Grid:SetThemes(Info.Themes);
		Grid.DisplayFrame = Holder;

		Groupbox:AddBlank(Info.BlankSize or 6);
		Groupbox:Resize();

		Options[Idx] = Grid;

		return Grid;
	end;

	-- Segmented selector:  [ Clean ] [ Dark ] [ Cyber ]   (a pill slides to the active segment)
	-- Info: Text, Values, Default, Callback
	function Funcs:AddSelector(Idx, Info)
		assert(type(Info.Values) == 'table' and #Info.Values > 0, 'AddSelector: Missing `Values` list.');

		local Selector = {
			Value = Info.Default or Info.Values[1];
			Values = Info.Values;
			Type = 'Selector';
			Callback = Info.Callback or function(Value) end;
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		if Info.Text then
			Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 12); TextSize = 13; Text = Info.Text; TextXAlignment = Enum.TextXAlignment.Left;
				TextYAlignment = Enum.TextYAlignment.Bottom; ZIndex = 5; Parent = Container;
			});

			Groupbox:AddBlank(4);
		end;

		-- more than four options do not fit in one row (the names get squeezed together): they wrap into rows of 3-4 equal segments
		local Count = #Selector.Values;
		local Cols = Count > 4 and math.ceil(Count / math.ceil(Count / 4)) or Count;
		local Rows = math.ceil(Count / Cols);

		local function CellPos(Index, OffX, OffY)
			return UDim2.new(((Index - 1) % Cols) / Cols, OffX, math.floor((Index - 1) / Cols) / Rows, OffY);
		end;

		local Outer = Library:Create('Frame', {
			BackgroundTransparency = 1; BorderSizePixel = 0; Size = UDim2.new(1, -4, 0, TouchSize(24) * Rows); ZIndex = 5; Parent = Container;
		});

		local Track = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor; BorderSizePixel = 0; Size = UDim2.new(1, 0, 1, 0); ZIndex = 6; Parent = Outer;
		});
		Library:AddCorner(Track, 6);
		Library:AddStroke(Track, 'BorderColor');
		Library:AddToRegistry(Track, { BackgroundColor3 = 'MainColor'; });

		local Pill = Library:Create('Frame', {
			BackgroundColor3 = Library.AccentColor; BackgroundTransparency = 0.8; BorderSizePixel = 0;
			Position = CellPos(1, 3, 3); Size = UDim2.new(1 / Cols, -6, 1 / Rows, -6); ZIndex = 7; Parent = Track;
		});
		Library:AddCorner(Pill, 4);
		Library:AddStroke(Pill, 'AccentColor');
		Library:AddToRegistry(Pill, { BackgroundColor3 = 'AccentColor'; });

		local Segments = {};


		for Index, Name in ipairs(Selector.Values) do
			local Seg = Library:Create('Frame', {
				BackgroundTransparency = 1; BorderSizePixel = 0; Position = CellPos(Index, 0, 0);
				Size = UDim2.new(1 / Cols, 0, 1 / Rows, 0); ZIndex = 8; Parent = Track;
			});

			local Label = Library:CreateLabel({
				Size = UDim2.new(1, -4, 1, 0); Position = UDim2.fromOffset(2, 0); Font = Library.FontMedium; TextSize = Cols > 3 and 11 or 12; Text = Name;
				TextTruncate = Enum.TextTruncate.AtEnd; ZIndex = 9; Parent = Seg;
			});


			Segments[Name] = { Seg = Seg; Label = Label; Index = Index; };

			Library:OnTap(Seg, function(Input)
				if Library:MouseIsOverOpenedFrame(Input) then
					return;
				end;


				Selector:SetValue(Name);
				Library:AttemptSave();
			end);
		end;

		function Selector:Display(Instant)
			for Name, S in next, Segments do
				local On = Name == Selector.Value;
				Library.RegistryMap[S.Label].Properties.TextColor3 = On and 'AccentColor' or 'DimFontColor';
				Library:Tween(S.Label, { TextColor3 = On and Library.AccentColor or Library.DimFontColor }, Instant and 0 or 0.25);
			end;

			local Active = Segments[Selector.Value];
			if Active then
				Library:Tween(Pill, { Position = CellPos(Active.Index, 3, 3) }, Instant and 0 or 0.4);
			end;
		end;

		function Selector:SetValue(Val)
			if not Segments[Val] then
				return;
			end;

			Selector.Value = Val;
			Selector:Display();

			Library:SafeCallback(Selector.Callback, Selector.Value);
			Library:SafeCallback(Selector.Changed, Selector.Value);
		end;

		function Selector:OnChanged(Func)
			Selector.Changed = Library:ChainCallback(Selector.Changed, Func);
			Func(Selector.Value);
		end;


		Selector:Display(true);
		Groupbox:AddBlank(Info.BlankSize or 6);
		Groupbox:Resize();

		Options[Idx] = Selector;

		return Selector;
	end;

	-- Multi-select list with check boxes:  [x] Particles  [x] Glow  [ ] Blur
	-- Value is a dictionary { Name = true }. Info: Text, Values, Default (list or dictionary), Callback
	function Funcs:AddChecklist(Idx, Info)
		assert(type(Info.Values) == 'table' and #Info.Values > 0, 'AddChecklist: Missing `Values` list.');

		local Checklist = {
			Value = {};
			Values = Info.Values;
			Type = 'Checklist';
			Callback = Info.Callback or function(Value) end;
		};

		if type(Info.Default) == 'table' then
			for Key, Val in next, Info.Default do
				if type(Key) == 'number' then
					Checklist.Value[Val] = true;
				elseif Val then
					Checklist.Value[Key] = true;
				end;
			end;
		end;

		local Groupbox = self;
		local Container = Groupbox.Container;

		if Info.Text then
			Library:CreateLabel({
				Size = UDim2.new(1, 0, 0, 12); TextSize = 13; Text = Info.Text; TextXAlignment = Enum.TextXAlignment.Left;
				TextYAlignment = Enum.TextYAlignment.Bottom; ZIndex = 5; Parent = Container;
			});

			Groupbox:AddBlank(4);
		end;

		local RowHeight = TouchSize(20);
		local BoxSize = TouchSize(14);

		local Holder = Library:Create('Frame', {
			BackgroundTransparency = 1; BorderSizePixel = 0; Size = UDim2.new(1, -4, 0, #Info.Values * RowHeight); ZIndex = 5; Parent = Container;
		});
		Library:Create('UIListLayout', { FillDirection = Enum.FillDirection.Vertical; SortOrder = Enum.SortOrder.LayoutOrder; Parent = Holder; });

		local Rows = {};

		local function Display(Name, Instant)
			local R = Rows[Name];
			local On = Checklist.Value[Name] == true;
			local Time = Instant and 0 or nil;

			Library.RegistryMap[R.Stroke].Properties.Color = On and 'AccentColor' or 'BorderColor';
			Library:Tween(R.Stroke, { Color = On and Library.AccentColor or Library.BorderColor }, Time or 0.25);

			Library:Tween(R.Fill, {
				Size = On and UDim2.fromScale(1, 1) or UDim2.fromScale(0, 0); BackgroundTransparency = On and 0 or 1;
			}, Time or 0.3, On and Enum.EasingStyle.Back or Enum.EasingStyle.Quint);

			Library.RegistryMap[R.Label].Properties.TextColor3 = On and 'FontColor' or 'DimFontColor';
			Library:Tween(R.Label, { TextColor3 = On and Library.FontColor or Library.DimFontColor }, Time or 0.25);
		end;

		for Index, Name in ipairs(Info.Values) do
			local Row = Library:Create('Frame', {
				BackgroundTransparency = 1; BorderSizePixel = 0; LayoutOrder = Index; Size = UDim2.new(1, 0, 0, RowHeight); ZIndex = 5; Parent = Holder;
			});

			local Box = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0, 0.5); BackgroundColor3 = Library.MainColor; BorderSizePixel = 0;
				Position = UDim2.new(0, 0, 0.5, 0); Size = UDim2.fromOffset(BoxSize, BoxSize); ZIndex = 6; Parent = Row;
			});
			Library:AddCorner(Box, 4);
			local Stroke = Library:AddStroke(Box, 'BorderColor');
			Library:AddToRegistry(Box, { BackgroundColor3 = 'MainColor'; });

			local Fill = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Library.AccentColor; BackgroundTransparency = 1; BorderSizePixel = 0;
				Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromScale(0, 0); ZIndex = 7; Parent = Box;
			});
			Library:AddCorner(Fill, 4);
			Library:AddToRegistry(Fill, { BackgroundColor3 = 'AccentColor'; });

			local Label = Library:CreateLabel({
				Position = UDim2.new(0, BoxSize + 8, 0, 0); Size = UDim2.new(1, -(BoxSize + 8), 1, 0); TextSize = 13; Text = Name;
				TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 6; Parent = Row;
			});

			Rows[Name] = { Stroke = Stroke; Fill = Fill; Label = Label; };

			Library:OnTap(Row, function(Input)
				if Library:MouseIsOverOpenedFrame(Input) then
					return;
				end;

				Checklist:SetItem(Name, not Checklist.Value[Name]);
				Library:AttemptSave();
			end);
		end;

		local function Fire()
			Library:SafeCallback(Checklist.Callback, Checklist.Value);
			Library:SafeCallback(Checklist.Changed, Checklist.Value);
		end;

		function Checklist:SetItem(Name, Bool)
			if not Rows[Name] then
				return;
			end;

			Checklist.Value[Name] = Bool and true or nil;
			Display(Name);
			Fire();
		end;

		function Checklist:SetValue(Dict)
			Checklist.Value = {};

			for Key, Val in next, Dict or {} do
				if type(Key) == 'number' then
					Checklist.Value[Val] = true;
				elseif Val then
					Checklist.Value[Key] = true;
				end;
			end;

			for Name in next, Rows do
				Display(Name);
			end;
			Fire();
		end;

		function Checklist:OnChanged(Func)
			Checklist.Changed = Library:ChainCallback(Checklist.Changed, Func);
			Func(Checklist.Value);
		end;

		for Name in next, Rows do
			Display(Name, true);
		end;

		Groupbox:AddBlank(Info.BlankSize or 6);
		Groupbox:Resize();

		Options[Idx] = Checklist;

		return Checklist;
	end;

	-- Collapsible section:  Advanced Settings  >   - returns a dependency box that opens / closes with the row
	function Funcs:AddAdvanced(Text, Opts)
		Opts = Opts or {};

		local Groupbox = self;
		local Container = Groupbox.Container;
		local State = { Value = Opts.Default == true; };

		local Row = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor; BackgroundTransparency = 0.55; BorderSizePixel = 0;
			Size = UDim2.new(1, -4, 0, TouchSize(22)); ZIndex = 5; Parent = Container;
		});
		Library:AddCorner(Row, 5);
		Library:AddToRegistry(Row, { BackgroundColor3 = 'MainColor'; });

		Library:CreateLabel({
			Position = UDim2.new(0, 8, 0, 0); Size = UDim2.new(1, -30, 1, 0); Font = Library.FontMedium; TextSize = 13; Text = Text;
			TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 6; Parent = Row;
		});

		local Arrow = Library:CreateLabel({
			AnchorPoint = Vector2.new(1, 0.5); Position = UDim2.new(1, -8, 0.5, 0); Size = UDim2.fromOffset(14, 14); Font = Library.FontBold;
			Text = '>'; TextSize = 13; Rotation = State.Value and 90 or 0; ZIndex = 6; Parent = Row;
		});
		Arrow.TextColor3 = Library.AccentColor;
		Library.RegistryMap[Arrow].Properties.TextColor3 = 'AccentColor';

		Row.MouseEnter:Connect(function() Library:Tween(Row, { BackgroundTransparency = 0.3 }, 0.2); end);
		Row.MouseLeave:Connect(function() Library:Tween(Row, { BackgroundTransparency = 0.55 }, 0.3); end);

		Groupbox:AddBlank(4);

		local Box = Groupbox:AddDependencyBox();
		Box:SetupDependencies({ { State, true } });

		Library:OnTap(Row, function(Input)
			if Library:MouseIsOverOpenedFrame(Input) then
				return;
			end;

			State.Value = not State.Value;
			Library:Tween(Arrow, { Rotation = State.Value and 90 or 0 }, 0.3);
			Box:Update();
		end);

		Box.State = State;

		return Box;
	end;

	-- Live bar graph that samples a function a few times per second (read-only; the data is real, e.g. FPS or ping)
	-- Info: Text, Min, Max, Suffix, Sample = function() return number end, Samples, Interval, Height
	function Funcs:AddGraph(Idx, Info)
		local Graph = {
			Type = 'Graph'; Value = 0; History = {};
			Min = Info.Min or 0; Max = Info.Max or 100; Samples = Info.Samples or 30;
			Interval = Info.Interval or 0.25; Elapsed = 0; Sample = Info.Sample or function() return 0; end;
		};

		local Groupbox = self;
		local Container = Groupbox.Container;

		local Header = Library:Create('Frame', {
			BackgroundTransparency = 1; BorderSizePixel = 0; Size = UDim2.new(1, -4, 0, 14); ZIndex = 5; Parent = Container;
		});

		Library:CreateLabel({
			Size = UDim2.new(0.6, 0, 1, 0); TextSize = 13; Text = Info.Text or ''; TextXAlignment = Enum.TextXAlignment.Left; ZIndex = 5; Parent = Header;
		});

		local ValueLabel = Library:CreateLabel({
			AnchorPoint = Vector2.new(1, 0); Position = UDim2.new(1, 0, 0, 0); Size = UDim2.new(0.4, 0, 1, 0); Font = Library.FontBold;
			Text = '--'; TextSize = 12; TextXAlignment = Enum.TextXAlignment.Right; ZIndex = 5; Parent = Header;
		});
		ValueLabel.TextColor3 = Library.AccentColor;
		Library.RegistryMap[ValueLabel].Properties.TextColor3 = 'AccentColor';

		Groupbox:AddBlank(3);

		local Plot = Library:Create('Frame', {
			BackgroundColor3 = Library.MainColor; BorderSizePixel = 0; ClipsDescendants = true;
			Size = UDim2.new(1, -4, 0, TouchSize(Info.Height or 36)); ZIndex = 5; Parent = Container;
		});
		Library:AddCorner(Plot, 5);
		Library:AddStroke(Plot, 'BorderColor');
		Library:AddToRegistry(Plot, { BackgroundColor3 = 'MainColor'; });

		Graph.Plot = Plot;

		local Bars = {};
		for I = 1, Graph.Samples do
			Bars[I] = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0, 1); BackgroundColor3 = Library.AccentColor; BackgroundTransparency = 0.6 - 0.5 * (I / Graph.Samples);
				BorderSizePixel = 0; Position = UDim2.new((I - 1) / Graph.Samples, 0, 1, 0); Size = UDim2.new(1 / Graph.Samples, -1, 0.03, 0);
				ZIndex = 6; Parent = Plot;
			});
			Library:AddToRegistry(Bars[I], { BackgroundColor3 = 'AccentColor'; });
		end;

		function Graph:Push(Value)
			Graph.Value = Value;

			table.insert(Graph.History, Value);
			if #Graph.History > Graph.Samples then
				table.remove(Graph.History, 1);
			end;

			local Offset = Graph.Samples - #Graph.History;
			local Range = math.max(Graph.Max - Graph.Min, 1e-6);

			for I = 1, Graph.Samples do
				local V = Graph.History[I - Offset];
				local H = V and math.clamp((V - Graph.Min) / Range, 0, 1) or 0;
				Bars[I].Size = UDim2.new(1 / Graph.Samples, -1, math.max(H * 0.94, 0.03), 0);
			end;

			ValueLabel.Text = string.format('%d%s', math.floor(Value + 0.5), Info.Suffix or '');
		end;

		table.insert(Library.Graphs, Graph);
		Library:_EnsureGraphTicker();

		local Ok, First = pcall(Graph.Sample);
		if Ok and type(First) == 'number' then
			Graph:Push(First);
		end;

		Groupbox:AddBlank(Info.BlankSize or 6);
		Groupbox:Resize();

		Options[Idx] = Graph;

		return Graph;
	end;
	function Funcs:AddDependencyBox()
		local Depbox = {
			Dependencies = {};
		};
		
		local Groupbox = self;
		local Container = Groupbox.Container;

		local Holder = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(1, 0, 0, 0);
			Visible = false;
			Parent = Container;
		});

		local Frame = Library:Create('Frame', {
			BackgroundTransparency = 1;
			Size = UDim2.new(1, 0, 1, 0);
			Visible = true;
			Parent = Holder;
		});

		local Layout = Library:Create('UIListLayout', {
			FillDirection = Enum.FillDirection.Vertical;
			SortOrder = Enum.SortOrder.LayoutOrder;
			Parent = Frame;
		});

		function Depbox:Resize()
			Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
			Groupbox:Resize();
		end;

		Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
			Depbox:Resize();
		end);

		Holder:GetPropertyChangedSignal('Visible'):Connect(function()
			Depbox:Resize();
		end);

		function Depbox:Update()
			for _, Dependency in next, Depbox.Dependencies do
				local Elem = Dependency[1];
				local Value = Dependency[2];

				if if Elem.Multi then not table.find(Elem:GetActiveValues(), Value) else Elem.Value ~= Value then
					Holder.Visible = false;
					Depbox:Resize();
					return;
				end;
			end;

			Holder.Visible = true;
			Depbox:Resize();
		end;

		function Depbox:SetupDependencies(Dependencies)
			for _, Dependency in next, Dependencies do
				assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
				assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
				assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
			end;

			Depbox.Dependencies = Dependencies;
			Depbox:Update();
		end;

		Depbox.Container = Frame;

		setmetatable(Depbox, BaseGroupbox);

		table.insert(Library.DependencyBoxes, Depbox);

		return Depbox;
	end;

	BaseGroupbox.__index = Funcs;
	BaseGroupbox.__namecall = function(Table, Key, ...)
		return Funcs[Key](...);
	end;
end;

-- < Create other UI elements >
do
	Library.NotificationArea = Library:Create('Frame', {
		BackgroundTransparency = 1;
		Position = UDim2.new(0, 14, 0, 40);
		Size = UDim2.new(0, 520, 0, 600);
		ZIndex = 100;
		Parent = ScreenGui;
	});

	Library:Create('UIListLayout', {
		Padding = UDim.new(0, 0);
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		Parent = Library.NotificationArea;
	});

	local WatermarkOuter = Library:Create('Frame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 100, 0, -25);
		Size = UDim2.new(0, 213, 0, 24);
		ZIndex = 200;
		Visible = false;
		Parent = ScreenGui;
	});

	local WatermarkInner = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderSizePixel = 0;
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 201;
		Parent = WatermarkOuter;
	});

	Library:AddCorner(WatermarkInner, 6);
	Library:AddStroke(WatermarkInner, 'BorderColor');

	Library:AddToRegistry(WatermarkInner, {
		BackgroundColor3 = 'MainColor';
	});

	local WatermarkAccent = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 6, 0, 0);
		Size = UDim2.new(1, -12, 0, 2);
		ZIndex = 203;
		Parent = WatermarkInner;
	});

	Library:AddToRegistry(WatermarkAccent, {
		BackgroundColor3 = 'AccentColor';
	});

	Library:Create('UIGradient', {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		});
		Parent = WatermarkAccent;
	});

	local WatermarkLabel = Library:CreateLabel({
		Position = UDim2.new(0, 10, 0, 0);
		Size = UDim2.new(1, -20, 1, 0);
		TextSize = 13;
		TextXAlignment = Enum.TextXAlignment.Left;
		ZIndex = 203;
		Parent = WatermarkInner;
	});

	Library.Watermark = WatermarkOuter;
	Library.WatermarkText = WatermarkLabel;
	Library:MakeDraggable(Library.Watermark);

	local KeybindOuter = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0, 0.5);
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 10, 0.5, 0);
		Size = UDim2.new(0, 210, 0, 32);
		Visible = false;
		ZIndex = 100;
		Parent = ScreenGui;
	});

	local KeybindInner = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BorderSizePixel = 0;
		ClipsDescendants = true;
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 101;
		Parent = KeybindOuter;
	});

	Library:AddCorner(KeybindInner, 6);
	Library:AddStroke(KeybindInner, 'BorderColor');

	Library:AddToRegistry(KeybindInner, {
		BackgroundColor3 = 'MainColor';
	}, true);

	local ColorFrame = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 8, 0, 24);
		Size = UDim2.new(1, -16, 0, 1);
		ZIndex = 102;
		Parent = KeybindInner;
	});

	Library:AddToRegistry(ColorFrame, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	Library:Create('UIGradient', {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		});
		Parent = ColorFrame;
	});

	local KeybindLabel = Library:CreateLabel({
		Size = UDim2.new(1, -20, 0, 24);
		Position = UDim2.fromOffset(10, 0),
		Font = Library.FontBold;
		TextSize = 13;
		TextXAlignment = Enum.TextXAlignment.Left,

		Text = 'Keybinds';
		ZIndex = 104;
		Parent = KeybindInner;
	});

	local KeybindContainer = Library:Create('Frame', {
		BackgroundTransparency = 1;
		Size = UDim2.new(1, 0, 1, -28);
		Position = UDim2.new(0, 0, 0, 28);
		ZIndex = 1;
		Parent = KeybindInner;
	});

	Library:Create('UIListLayout', {
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		Parent = KeybindContainer;
	});

	Library:Create('UIPadding', {
		PaddingLeft = UDim.new(0, 10),
		Parent = KeybindContainer,
	})

	Library.KeybindFrame = KeybindOuter;
	Library.KeybindContainer = KeybindContainer;
	Library:MakeDraggable(KeybindOuter);
end;

function Library:SetWatermarkVisibility(Bool)
	Library:FadeFrame(Library.Watermark, Bool);
end;

function Library:SetWatermark(Text)
	local X, Y = Library:GetTextBounds(Text, Library.Font, 13);
	Library:Tween(Library.Watermark, { Size = UDim2.new(0, X + 22, 0, math.max(Y + 12, 24)) }, 0.3);

	Library.WatermarkText.Text = Text;
end;

function Library:Notify(Text, Time, SoundId)
	local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 13);

	local Width = XSize + 32;
	local Height = YSize + 18;
	local Gap = 6;

	-- the holder reserves space in the list; growing/shrinking it makes the other toasts glide
	local Holder = Library:Create('Frame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Size = UDim2.new(0, Width, 0, 0);
		ZIndex = 100;
		Parent = Library.NotificationArea;
	});

	local Card = Library:CreateCanvas({
		BackgroundColor3 = Library.MainColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, -Width - 24, 0, 0);
		Size = UDim2.new(1, 0, 0, Height);
		ZIndex = 101;
		Parent = Holder;
	});

	Library:AddCorner(Card, 6);
	Library:SetGroupTransparency(Card, 1);

	Library:AddToRegistry(Card, {
		BackgroundColor3 = 'MainColor';
	}, true);

	local Outline = Library:Create('Frame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = UDim2.fromOffset(1, 1);
		Size = UDim2.new(1, -2, 1, -2);
		ZIndex = 106;
		Parent = Card;
	});

	Library:AddCorner(Outline, 5);
	Library:AddStroke(Outline, 'BorderColor');

	-- soft accent wash from the left edge
	local Wash = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Size = UDim2.new(0.6, 0, 1, 0);
		ZIndex = 102;
		Parent = Card;
	});

	Library:AddToRegistry(Wash, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	Library:Create('UIGradient', {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		});
		Parent = Wash;
	});

	local LeftColor = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Size = UDim2.new(0, 3, 1, 0);
		ZIndex = 104;
		Parent = Card;
	});

	Library:AddToRegistry(LeftColor, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	local NotifyLabel = Library:CreateLabel({
		Position = UDim2.new(0, 14, 0, 0);
		Size = UDim2.new(1, -20, 1, -2);
		Text = Text;
		TextXAlignment = Enum.TextXAlignment.Left;
		TextSize = 13;
		ZIndex = 105;
		Parent = Card;
	}, true);

	-- countdown bar
	local Progress = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BackgroundTransparency = 0.2;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 0, 1, -2);
		Size = UDim2.new(1, 0, 0, 2);
		ZIndex = 105;
		Visible = typeof(Time) ~= "Instance";
		Parent = Card;
	});

	Library:AddToRegistry(Progress, {
		BackgroundColor3 = 'AccentColor';
	}, true);

	if SoundId then
		pcall(function()
			local Sound = Instance.new('Sound');
			Sound.SoundId = (type(SoundId) == 'number' and 'rbxassetid://' .. SoundId) or tostring(SoundId);
			Sound.Volume = 1;
			Sound.PlayOnRemove = true;
			Sound.Parent = ScreenGui;
			Sound:Destroy();
		end);
	end;

	-- in: make room, then slide + fade the card in
	Library:Tween(Holder, { Size = UDim2.new(0, Width, 0, Height + Gap) }, 0.35);
	Library:Tween(Card, { Position = UDim2.new(0, 0, 0, 0) }, 0.6);
	Library:SetGroupTransparency(Card, 0, 0.45);

	task.spawn(function()
		if typeof(Time) == "Instance" then
			Time.Destroying:Wait();
		else
			local Duration = Time or 5;
			TweenService:Create(Progress, TweenInfo.new(Duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play();
			task.wait(Duration);
		end

		-- out: slide back + fade, then collapse the gap so the rest glide up
		Library:Tween(Card, { Position = UDim2.new(0, -Width - 24, 0, 0) }, 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
		Library:SetGroupTransparency(Card, 1, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In);

		task.wait(0.4 * Library.AnimationSpeed);

		Library:Tween(Holder, { Size = UDim2.new(0, Width, 0, 0) }, 0.3);

		task.wait(0.32 * Library.AnimationSpeed);

		Holder:Destroy();
	end);
end;
-- ===== Theme FX engine =====
-- Layered, data-driven scenes (Base / Atmosphere / Decor / Particles / Lighting) drawn by a Renderer.
-- * One shared RenderStepped connection drives every renderer, only while one is visible AND animated.
-- * Updaters are throttled per Performance profile (24 / 30 / 45 fps), particles come from a capped budget,
--   and an adaptive guard shrinks the budget when the real frame rate drops.
-- * A scene that errors is dropped (warn) - effects can never take the menu down with them.
local FXRandom = Random.new();

local FX = {
	Settings = {
		Background = true; Particles = true; Decorations = true; Animations = true;
		Transitions = true; Ambient = true; Intensity = 'Medium'; Performance = 'Balanced';
	};

	-- Cap = max particles per renderer, Scale = multiplier on a scene's own counts, Fps = update rate of animated layers
	Profiles = {
		Minimal   = { Background = false; Decor = false; Ambient = false; Cap = 0;  Scale = 0;   Fps = 0;  Transition = 'none';  };
		Balanced  = { Background = true;  Decor = true;  Ambient = true;  Cap = 26; Scale = 0.7; Fps = 30; Transition = 'light'; };
		Beautiful = { Background = true;  Decor = true;  Ambient = true;  Cap = 52; Scale = 1;   Fps = 45; Transition = 'full';  };
		Extreme   = { Background = true;  Decor = true;  Ambient = true;  Cap = 96; Scale = 1.5; Fps = 60; Transition = 'full';  };
	};
	IntensityMul = { Off = 0; Low = 0.4; Medium = 1; High = 1.6; Extreme = 2.4; };
	LayerOrder = { 'Base', 'Atmosphere', 'Decor', 'Particles', 'Lighting' };

	Scenes = {}; SceneOrder = {}; SceneListeners = {}; Transitions = {}; Renderers = {};
	SceneName = 'None'; Scene = nil;
	AutoScale = 1; TimeScale = 1; FrameAvg = 1 / 60;
	Mobile = Library.IsMobile and 0.6 or 1;
	RebuildToken = 0; TransToken = 0; GuardClock = 0; Slow = 0;
};

Library.FX = FX;

local function RGB(R, G, B) return Color3.fromRGB(R, G, B); end;
local function BG() return Library.BackgroundColor; end;
local function Tint(Base, Target, T) -- Base is a color *function*, result follows the theme
	return function() return Base():Lerp(Target, T); end;
end;
local function Seq(...) -- ColorSequence from color values / color functions, evenly spaced (needs >= 2)
	local Fns = { ... };
	local N = #Fns;
	return function()
		local Keys = {};
		for I, Fn in ipairs(Fns) do
			Keys[I] = ColorSequenceKeypoint.new((I - 1) / (N - 1), type(Fn) == 'function' and Fn() or Fn);
		end;
		return ColorSequence.new(Keys);
	end;
end;
local function NS(...) -- NumberSequence from (time, value, time, value ...)
	local A = { ... };
	local Keys = {};
	for I = 1, #A, 2 do
		table.insert(Keys, NumberSequenceKeypoint.new(A[I], A[I + 1]));
	end;
	return NumberSequence.new(Keys);
end;
local function Round(Inst, Scale, Offset)
	local Corner = Instance.new('UICorner');
	Corner.CornerRadius = UDim.new(Scale or 0, Offset or 0);
	Corner.Parent = Inst;
	return Corner;
end;
local function Roll(Range) -- {min, max} -> random number, plain number -> itself
	if type(Range) == 'table' then
		return Range[1] + (Range[2] - Range[1]) * FXRandom:NextNumber();
	end;
	return Range or 0;
end;
local function Tw(Inst, Props, Time, Style, Dir, Delay)
	local Speed = Library.AnimationSpeed;
	local Tween = TweenService:Create(Inst, TweenInfo.new(Time * Speed, Style or Enum.EasingStyle.Quint, Dir or Enum.EasingDirection.Out, 0, false, (Delay or 0) * Speed), Props);
	Tween:Play();
	return Tween;
end;

-- ---------------------------------------------------------------- renderer
local RM = {};
RM.__index = RM;

function FX:CreateRenderer(Holder, Options)
	local R = setmetatable({
		Holder = Holder; Options = Options or {}; Layers = {}; Updaters = {};
		Time = 0; Acc = 0; Used = 0; Active = false; Scene = nil; Tweens = {}; Gen = 0;
	}, RM);

	R.Z = R.Options.ZIndex or Holder.ZIndex;

	for _, Name in ipairs(FX.LayerOrder) do
		local Layer = Instance.new('Frame');
		Layer.Name = 'FX_' .. Name;
		Layer.BackgroundTransparency = 1;
		Layer.BorderSizePixel = 0;
		Layer.ClipsDescendants = not R.Options.NoClip;
		Layer.Size = UDim2.fromScale(1, 1);
		Layer.ZIndex = R.Z;
		Layer.Parent = Holder;
		R.Layers[Name] = Layer;
	end;

	R.E = R:Get();
	FX.Renderers[R] = true;

	return R;
end;

-- effective settings (a renderer can pin its own via Options)
function RM:Get()
	local O, S = self.Options, FX.Settings;
	local function Pick(Key)
		if O[Key] ~= nil then return O[Key]; end;
		return S[Key];
	end;

	local Profile = FX.Profiles[Pick('Performance')] or FX.Profiles.Balanced;
	local Animated = Pick('Animations') and Profile.Fps > 0;

	return {
		Profile = Profile;
		Intensity = Pick('Intensity');
		Animated = Animated;
		Background = Pick('Background') and Profile.Background;
		Decor = Pick('Decorations') and Profile.Decor;
		Particles = Pick('Particles') and Profile.Cap > 0 and Pick('Intensity') ~= 'Off' and Animated;
		Ambient = Pick('Ambient') and Profile.Ambient and Animated;
		Fps = math.min(Profile.Fps, Library.IsMobile and 24 or 60);
	};
end;

function RM:Size()
	local Source = self.Options.SizeFrom or self.Holder;
	local Size = Source.AbsoluteSize;
	if Size.X < 50 or Size.Y < 50 then
		return self.Options.FallbackSize or Vector2.new(700, 520);
	end;
	return Size;
end;

function RM:Shown()
	if self.Options.Visible then
		return self.Options.Visible();
	end;
	return self.Holder.Visible;
end;

function RM:Apply()
	local E = self:Get();
	self.E = E;

	local L = self.Layers;
	L.Base.Visible = E.Background;
	L.Atmosphere.Visible = E.Background;
	L.Decor.Visible = E.Decor;
	L.Particles.Visible = E.Particles;
	L.Lighting.Visible = E.Ambient;

	self.Active = self.Scene ~= nil and E.Animated and #self.Updaters > 0
		and (E.Background or E.Decor or E.Particles or E.Ambient);

	if self.Options.OnApply then
		pcall(self.Options.OnApply, self);
	end;

	FX:_Sync();
end;

function RM:Clear()
	for _, Layer in next, self.Layers do
		Layer:ClearAllChildren();
	end;
	table.clear(self.Updaters);
	self.Gen = self.Gen + 1;
	for _, Entry in ipairs(self.Tweens) do
		Entry.T:Cancel();
	end;
	self.Tweens = {};
	self.Used = 0;
	self.Time = 0;
	self.Acc = 0;
	self.Sigils = nil;
end;

function RM:SetScene(Scene)
	self:Clear();
	self.Scene = Scene;
	self.E = self:Get();

	if Scene and Scene.Build then
		local Ok, Err = pcall(Scene.Build, self);
		if not Ok then
			warn('[Library.FX] scene "' .. tostring(Scene.Name) .. '" failed: ' .. tostring(Err));
			self:Clear();
			self.Scene = nil;
		end;
	end;

	self:Apply();
end;

function RM:Tick(Fn, LayerName)
	table.insert(self.Updaters, { Fn = Fn; Layer = self.Layers[LayerName or 'Particles'] });
end;

-- ---- engine-driven animation -------------------------------------------------------------------------
-- Almost everything that moves is a TweenService tween that repeats forever: the engine interpolates it every
-- display frame (smooth at 60+ fps) and no script runs per frame. Tweens are registered per layer so they can be
-- paused when the menu is closed, when a layer is switched off, or when animations are off.

-- interpolate numbers, UDim2, Color3, Vector2 ...
local function Mix(A, B, T)
	if type(A) == 'number' then
		return A + (B - A) * T;
	end;
	return A:Lerp(B, T);
end;

local Linear = Enum.EasingStyle.Linear;
local Sine = Enum.EasingStyle.Sine;
local EOut = Enum.EasingDirection.Out;
local EInOut = Enum.EasingDirection.InOut;

-- start / stop one registered tween according to the current state
function RM:Sync1(Entry, Run)
	local State = Entry.T.PlaybackState;

	if State == Enum.PlaybackState.Completed or State == Enum.PlaybackState.Cancelled then
		return false;
	end;

	local Should = Run and Entry.Layer.Visible;
	if Should then
		if State == Enum.PlaybackState.Begin or State == Enum.PlaybackState.Paused then
			Entry.T:Play();
		end;
	elseif State == Enum.PlaybackState.Playing then
		Entry.T:Pause();
	end;

	return true;
end;

-- called when the menu opens / closes and whenever a layer or the animation switch changes
function RM:SyncTweens()
	local Run = self.E ~= nil and self.E.Animated and self:Shown();
	local Keep = {};

	for _, Entry in ipairs(self.Tweens) do
		if self:Sync1(Entry, Run) then
			table.insert(Keep, Entry);
		end;
	end;

	self.Tweens = Keep;
end;

-- create (and register) a tween; Time / Delay follow Library.AnimationSpeed and the Cinematic slow-down
function RM:Tween(Inst, Props, Time, Style, Dir, LayerName, Repeat, Reverses, Delay)
	local Speed = Library.AnimationSpeed / math.max(FX.TimeScale or 1, 0.1);
	local Info = TweenInfo.new(math.max(Time, 0.03) * Speed, Style or Linear, Dir or EOut, Repeat or 0, Reverses or false, (Delay or 0) * Speed);

	local Entry = { T = TweenService:Create(Inst, Info, Props); Layer = self.Layers[LayerName or 'Particles']; };
	table.insert(self.Tweens, Entry);

	self:Sync1(Entry, self.E ~= nil and self.E.Animated and self:Shown());

	return Entry.T;
end;

-- One-way cycle that never ends (a petal falling, a cloud drifting, a ring expanding): every property goes
-- From -> To in Dur seconds and starts over. The FIRST run begins P0 of the way through, so the scene is already
-- "mid-flight" when it appears instead of everything starting at the edge. Props = { Prop = { From, To } }.
function RM:Cycle(Inst, Props, Dur, LayerName, P0)
	P0 = P0 or FXRandom:NextNumber();
	local Gen = self.Gen;

	local First = {};
	for Prop, Range in next, Props do
		Inst[Prop] = Mix(Range[1], Range[2], P0);
		First[Prop] = Range[2];
	end;

	local function Loop()
		if Gen ~= self.Gen or not Inst.Parent then
			return;
		end;

		local To = {};
		for Prop, Range in next, Props do
			Inst[Prop] = Range[1];
			To[Prop] = Range[2];
		end;

		self:Tween(Inst, To, Dur, Linear, EOut, LayerName, -1);
	end;

	local Tween = self:Tween(Inst, First, math.max(Dur * (1 - P0), 0.05), Linear, EOut, LayerName);
	Tween.Completed:Once(function(State)
		if State == Enum.PlaybackState.Completed then
			Loop();
		end;
	end);
end;

-- Back-and-forth that never ends (sway, breathing, bobbing). Props = { Prop = { A, B } }, Half = seconds A -> B.
function RM:Sway(Inst, Props, Half, LayerName, Style)
	local To = {};
	for Prop, Range in next, Props do
		Inst[Prop] = Range[1];
		To[Prop] = Range[2];
	end;

	-- random head start so a group of sways does not move in lockstep
	self:Tween(Inst, To, Half, Style or Sine, EInOut, LayerName, -1, true, FXRandom:NextNumber() * Half);
end;
-- how many particles a scene may create right now (profile cap x intensity x auto scale x mobile)
function RM:Budget(Base)
	local E = self.E or self:Get();
	local N = math.floor(Base * (FX.IntensityMul[E.Intensity] or 1) * E.Profile.Scale * FX.AutoScale * FX.Mobile + 0.5);
	N = math.min(N, math.max(E.Profile.Cap - self.Used, 0));
	self.Used = self.Used + N;
	return N;
end;

-- create a GuiObject; function values become theme-aware (re-evaluated by UpdateColorsUsingRegistry)
function RM:New(Class, Props, Parent)
	local Inst = Instance.new(Class);

	if Inst:IsA('GuiObject') then
		Inst.BorderSizePixel = 0;
		Inst.ZIndex = self.Z;
	end;

	local Reg;
	for Key, Value in next, Props do
		if type(Value) == 'function' then
			Inst[Key] = Value();
			Reg = Reg or {};
			Reg[Key] = Value;
		else
			Inst[Key] = Value;
		end;
	end;

	if Reg then
		Library:AddToRegistry(Inst, Reg);
	end;

	Inst.Parent = Parent;
	return Inst;
end;

-- ---------------------------------------------------------------- shared loop
local function FXStep(Dt)
	FX.FrameAvg = FX.FrameAvg * 0.94 + Dt * 0.06;
	FX.GuardClock = FX.GuardClock + Dt;

	if FX.GuardClock >= 2 then
		FX.GuardClock = 0;
		FX:_Guard();
	end;

	local Scale = FX.TimeScale or 1;

	for R in next, FX.Renderers do
		if R.Active and R:Shown() then
			R.Acc = R.Acc + Dt;

			if R.Acc >= 1 / R.E.Fps then
				local Step = R.Acc * Scale;
				R.Acc = 0;
				R.Time = R.Time + Step;

				local Ups = R.Updaters;
				for I = #Ups, 1, -1 do
					local U = Ups[I];
					if U.Layer.Visible then
						local Ok, Err = pcall(U.Fn, R.Time, Step);
						if not Ok then
							warn('[Library.FX] updater removed: ' .. tostring(Err));
							table.remove(Ups, I);
						end;
					end;
				end;
			end;
		end;
	end;
end;

function FX:_Sync()
	local Need = false;
	for R in next, FX.Renderers do
		if R.Active and R:Shown() then
			Need = true;
			break;
		end;
	end;

	if Need and not FX.Conn then
		FX.FrameAvg = 1 / 60;
		FX.GuardClock = 0;
		FX.Slow = 0;
		FX.Conn = RenderStepped:Connect(FXStep);
	elseif (not Need) and FX.Conn then
		FX.Conn:Disconnect();
		FX.Conn = nil;
	end;

	-- engine tweens run only while the menu is open and the layer / animation switches allow it
	for R in next, FX.Renderers do
		R:SyncTweens();
	end;
end;

-- If the real frame rate stays under ~22 fps while effects run, shrink the particle budget (once every 4s at most)
function FX:_Guard()
	if FX.FrameAvg > 1 / 22 and FX.AutoScale > 0.3 then
		FX.Slow = FX.Slow + 1;

		if FX.Slow >= 2 then
			FX.Slow = 0;
			FX.AutoScale = math.max(FX.AutoScale * 0.6, 0.25);
			FX:QueueRebuild(0.1);
			Library:Notify('Visual effects were reduced to keep your FPS up', 4);
		end;
	else
		FX.Slow = 0;
	end;
end;

function FX:QueueRebuild(Delay)
	FX.RebuildToken = FX.RebuildToken + 1;
	local Token = FX.RebuildToken;

	task.delay(Delay or 0.1, function()
		if Token ~= FX.RebuildToken then
			return;
		end;

		for R in next, FX.Renderers do
			if R.Scene and not R.Options.Independent then
				R:SetScene(R.Scene);
			end;
		end;
	end);
end;

-- change several settings at once (one rebuild, one apply)
function FX:Configure(Tbl)
	local Rebuild = false;

	for Key, Value in next, Tbl do
		if FX.Settings[Key] ~= nil and FX.Settings[Key] ~= Value then
			FX.Settings[Key] = Value;

			if Key == 'Intensity' or Key == 'Performance' then
				Rebuild = true;
				FX.AutoScale = 1;
			end;
		end;
	end;

	for R in next, FX.Renderers do
		if not R.Options.Independent then
			R:Apply();
		end;
	end;

	if Rebuild then
		FX:QueueRebuild(0.05);
	end;

	FX:ApplyPanels();
end;

function FX:RegisterScene(Def)
	if not FX.Scenes[Def.Name] then
		table.insert(FX.SceneOrder, Def.Name);
	end;
	FX.Scenes[Def.Name] = Def;
end;

function FX:SetScene(Name)
	local Scene = FX.Scenes[Name];

	FX.Scene = Scene;
	FX.SceneName = Scene and Scene.Name or 'None';
	FX.RebuildToken = FX.RebuildToken + 1; -- cancels any queued rebuild: we are rebuilding right now

	if FX.Main then
		FX.Main:SetScene(Scene);
	end;

	-- the accessories around the window follow the scene (the window installs this hook)
	if FX.AccessoryHook then
		FX.AccessoryHook();
	end;

	FX:ApplyPanels();

	for _, Fn in ipairs(FX.SceneListeners) do
		pcall(Fn, FX.SceneName);
	end;
end;

function FX:GetStats()
	local Particles, Updaters, Renderers, Tweens = 0, 0, 0, 0;
	for R in next, FX.Renderers do
		Renderers = Renderers + 1;
		Particles = Particles + R.Used;
		Updaters = Updaters + #R.Updaters;
		Tweens = Tweens + #R.Tweens;
	end;

	return {
		Scene = FX.SceneName; Performance = FX.Settings.Performance; Intensity = FX.Settings.Intensity;
		Renderers = Renderers; Particles = Particles; Updaters = Updaters; Tweens = Tweens;
		AutoScale = FX.AutoScale; Running = FX.Conn ~= nil;
		FrameMs = FX.FrameAvg * 1000;
	};
end;

function FX:DestroyRenderer(R)
	FX.Renderers[R] = nil;
	R:Clear();
	for _, Layer in next, R.Layers do
		Layer:Destroy();
	end;
	FX:_Sync();
end;

function FX:Destroy()
	if FX.Conn then
		FX.Conn:Disconnect();
		FX.Conn = nil;
	end;
	FX.TransToken = FX.TransToken + 1;
	FX.RebuildToken = FX.RebuildToken + 1;
	for R in next, FX.Renderers do
		FX.Renderers[R] = nil;
	end;
end;

Library:OnUnload(function()
	FX:Destroy();
end);

-- groupboxes / tabboxes turn slightly translucent while a scene is drawn behind them
Library.Panels = setmetatable({}, { __mode = 'k' });

function Library:RegisterPanel(Frame)
	Library.Panels[Frame] = true;
	Frame.BackgroundTransparency = FX.PanelAlpha or 0;
end;

function FX:ApplyPanels()
	local Alpha = 0;
	if FX.Scene and FX.Main and FX.Main.E and FX.Main.E.Background then
		Alpha = FX.Scene.PanelAlpha or 0.3;
	end;

	FX.PanelAlpha = Alpha;
	for Panel in next, Library.Panels do
		if Panel.Parent then
			Library:Tween(Panel, { BackgroundTransparency = Alpha }, 0.5);
		end;
	end;
end;

-- ---------------------------------------------------------------- primitives
-- Moving things are engine tweens (RM:Cycle / RM:Sway); only the waves, the grid rows and the scan line need a
-- per-frame script. Spec transparencies follow Roblox (0 = solid, 1 = invisible).

function RM:Gradient(Spec)
	local F = self:New('Frame', {
		BackgroundColor3 = Color3.new(1, 1, 1);
		BackgroundTransparency = Spec.Alpha or 0;
		Position = Spec.Position or UDim2.new();
		Size = Spec.Size or UDim2.fromScale(1, 1);
	}, self.Layers[Spec.Layer or 'Base']);

	local G = self:New('UIGradient', {
		Color = Spec.Colors;
		Rotation = Spec.Rotation or 90;
		Transparency = Spec.Transparency or NumberSequence.new(0);
	}, F);

	if Spec.Drift then -- the colors slide slowly back and forth
		local Amount = Spec.DriftAmount or 0.15;
		self:Sway(G, { Offset = { Vector2.new(-Amount, -Amount), Vector2.new(Amount, Amount) } }, math.pi / Spec.Drift, Spec.Layer or 'Base');
	end;

	return F;
end;

-- Particles. Each one is an invisible "mover" that travels a path with a looping tween, and the particle itself
-- hangs off the mover so it can wobble, spin and twinkle with tweens of its own.
-- Spec: Layer, Count (budgeted), Shape (Circle / Square / Diamond / Petal / Bubble / Ember / Text), Size {min, max} px,
--       Vx, Vy (scale/sec ranges: the direction of travel), Spawn { X = {a, b}, Y = {c, d} } (start area for falling things),
--       Wobble { amp (fraction of the width), freqMin, freqMax }, Spin (deg/sec range), Alpha (transparency range),
--       Twinkle (0-1), LifeFade (fades out over its trip), Static (stars, or a spot given by Spawn), Colors, Chars / Column (Text),
--       Flip { min, max } seconds (a Petal turns edge-on and back while it falls), Gradient (a Petal is lighter at its base),
--       Build(R, Mover, Px, Color, Alpha) -> a custom particle (a whole flower, ...), it gets the same trip / wobble / spin
function RM:Emitter(Spec)
	local Count = self:Budget(Spec.Count or 10);
	if Count <= 0 then
		return;
	end;

	local LayerName = Spec.Layer or 'Particles';
	local Layer = self.Layers[LayerName];
	local Shape = Spec.Shape or 'Circle';
	local Colors = Spec.Colors or { Color3.new(1, 1, 1) };
	local Chars = Spec.Chars or '01';
	local IsText = Shape == 'Text';
	local Prop = IsText and 'TextTransparency' or 'BackgroundTransparency';
	local WindowSize = self:Size();

	for _ = 1, Count do
		local Px = Roll(Spec.Size or { 3, 6 });
		local Color = Colors[FXRandom:NextInteger(1, #Colors)];
		if type(Color) == 'function' then
			Color = Color();
		end;
		local Alpha = Roll(Spec.Alpha or { 0.4, 0.8 });

		local Mover = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Size = UDim2.fromOffset(0, 0);
		}, Layer);

		local Core, Halo;

		if Spec.Build then
			Core = Spec.Build(self, Mover, Px, Color, Alpha);
		elseif IsText then -- a falling column of characters, bright at the head
			local Rows = Spec.Column or 7;
			local Text = {};
			for K = 1, Rows do
				local C = FXRandom:NextInteger(1, #Chars);
				Text[K] = string.sub(Chars, C, C);
			end;

			Core = self:New('TextLabel', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Font = Enum.Font.Code;
				Position = UDim2.fromOffset(0, 0); Size = UDim2.fromOffset(Px, Px * 1.2 * Rows);
				Text = table.concat(Text, '\n'); TextColor3 = Color; TextSize = math.floor(Px); TextTransparency = Alpha;
			}, Mover);
			self:New('UIGradient', { Rotation = 90; Transparency = NS(0, 1, 0.7, 0.25, 1, 0); }, Core);
		else
			Core = self:New('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color; BackgroundTransparency = Alpha;
				Position = UDim2.fromOffset(0, 0); Rotation = Shape == 'Diamond' and 45 or 0;
				Size = Shape == 'Petal' and UDim2.fromOffset(Px * 1.7, Px) or UDim2.fromOffset(Px, Px);
			}, Mover);

			if Shape == 'Diamond' then
				Round(Core, 0, 1);
			elseif Shape ~= 'Square' then
				Round(Core, 0.5, 0);
			end;

			if Shape == 'Bubble' then
				local Stroke = Instance.new('UIStroke');
				Stroke.Color = Color3.new(1, 1, 1);
				Stroke.Thickness = 1;
				Stroke.Transparency = 0.45;
				Stroke.Parent = Core;
			end;

			if Shape == 'Ember' then -- bright core + a soft halo around it
				Core.ZIndex = self.Z + 1;
				Halo = self:New('Frame', {
					AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color; BackgroundTransparency = 0.82;
					Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromScale(4.4, 4.4);
				}, Core);
				Round(Halo, 0.5, 0);
			end;

			if Shape == 'Petal' and Spec.Gradient then -- lighter at the base, deeper at the tip (the gradient multiplies the white fill)
				Core.BackgroundColor3 = Color3.new(1, 1, 1);
				self:New('UIGradient', { Color = ColorSequence.new(Color:Lerp(Color3.new(1, 1, 1), 0.6), Color); }, Core);
			end;

			if Shape == 'Petal' and Spec.Flip then -- tumbling: the petal turns edge-on and back, like a real one falling
				self:Sway(Core, { Size = { UDim2.fromOffset(Px * 1.7, Px), UDim2.fromOffset(Px * 0.3, Px) } }, Roll(Spec.Flip), LayerName);
			end;
		end;

		-- the trip
		if Spec.Static then
			local Area = Spec.Spawn;
			Mover.Position = UDim2.fromScale(Area and Roll(Area.X) or FXRandom:NextNumber(), Area and Roll(Area.Y) or FXRandom:NextNumber());
			if Shape == 'Petal' then
				Core.Rotation = FXRandom:NextNumber() * 360;
			end;
		else
			local Vx = Roll(Spec.Vx or { -0.01, 0.01 });
			local Vy = Roll(Spec.Vy or { -0.05, -0.02 });
			local Spawn = Spec.Spawn;
			local FromX, FromY, ToX, ToY, Dur;

			if math.abs(Vy) >= math.abs(Vx) then -- mostly vertical: rising or falling
				FromY = Vy < 0 and 1.06 or -0.06;
				ToY = Vy < 0 and -0.06 or 1.06;
				FromX = FXRandom:NextNumber();

				if Spawn then
					FromX = Roll(Spawn.X);
					FromY = Roll(Spawn.Y);
				end;

				Dur = math.abs(ToY - FromY) / math.max(math.abs(Vy), 0.005);
				ToX = FromX + Vx * Dur;
			else -- mostly horizontal
				FromX = Vx < 0 and 1.06 or -0.06;
				ToX = Vx < 0 and -0.06 or 1.06;
				FromY = FXRandom:NextNumber();
				Dur = math.abs(ToX - FromX) / math.max(math.abs(Vx), 0.005);
				ToY = FromY + Vy * Dur;
			end;

			local P0 = FXRandom:NextNumber();
			self:Cycle(Mover, { Position = { UDim2.fromScale(FromX, FromY), UDim2.fromScale(ToX, ToY) } }, Dur, LayerName, P0);

			if Spec.LifeFade and not Spec.Build then
				self:Cycle(Core, { [Prop] = { Alpha, 1 } }, Dur, LayerName, P0);
				if Halo then
					self:Cycle(Halo, { BackgroundTransparency = { 0.82, 1 } }, Dur, LayerName, P0);
				end;
			end;
		end;

		if Spec.Twinkle and not Spec.LifeFade and not Spec.Build then
			self:Sway(Core, { [Prop] = { Alpha, Alpha + (1 - Alpha) * Spec.Twinkle } }, Roll({ 0.6, 1.8 }), LayerName);
		end;

		if Spec.Wobble then
			local Amp = Spec.Wobble[1] * WindowSize.X;
			self:Sway(Core, { Position = { UDim2.fromOffset(-Amp, 0), UDim2.fromOffset(Amp, 0) } }, math.pi / Roll({ Spec.Wobble[2], Spec.Wobble[3] }), LayerName);
		end;

		if Spec.Spin then
			local Speed = Roll(Spec.Spin);
			if math.abs(Speed) > 2 then
				local Base = Core.Rotation;
				self:Cycle(Core, { Rotation = { Base, Base + (Speed > 0 and 360 or -360) } }, 360 / math.abs(Speed), LayerName);
			end;
		end;
	end;
end;

-- Gusts of wind: long thin streaks that fade in and out at both ends and sweep across the scene, a little downhill.
-- Spec: Layer, Count, Color, Length {min, max} px, Thick {min, max} px, Alpha (transparency range), Duration {min, max} s, Drop (how far they sink, in window heights)
function RM:Wind(Spec)
	-- a handful of thin frames: not counted against the particle budget, but fewer on lighter profiles and none on Minimal / Off
	local E = self.E or self:Get();
	if E.Profile.Cap <= 0 or E.Intensity == 'Off' then
		return;
	end;
	local Count = math.max(math.floor((Spec.Count or 6) * math.clamp(E.Profile.Scale, 0.5, 1) + 0.5), 1);

	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Size = self:Size();
	local Drop = Spec.Drop or 0.18;
	local Tilt = -math.deg(math.atan2(Drop * Size.Y, 1.3 * Size.X)); -- the streak lies along its own path

	for _ = 1, Count do
		local Streak = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Color or Color3.new(1, 1, 1); BackgroundTransparency = Roll(Spec.Alpha or { 0.82, 0.93 });
			Rotation = Tilt; Size = UDim2.fromOffset(Roll(Spec.Length or { 160, 320 }), Roll(Spec.Thick or { 2, 4 }));
		}, Layer);
		Round(Streak, 0.5, 0);
		self:New('UIGradient', { Transparency = NS(0, 1, 0.5, 0, 1, 1); }, Streak);

		local FromY = FXRandom:NextNumber() * 0.9;
		self:Cycle(Streak, { Position = { UDim2.fromScale(1.15, FromY), UDim2.fromScale(-0.15, FromY + Drop) } }, Roll(Spec.Duration or { 5, 9 }), LayerName);
	end;
end;

-- Traveling waves made of thin bars. Every bar has its own crest -> body gradient, so each wave has a bright
-- lip on top (foam / molten crest) and fades to its body color below it. This is the one thing that has to be
-- calculated every frame (the shape is a sum of sines).
-- Spec: Layer, Top (bars hang from the top edge = water seen from below), Segments,
--       Bands = { { Body, Crest, Alpha (transparency), Height, Amp, Speed (negative = other direction), Freq } }
function RM:Waves(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local E = self.E or self:Get();

	-- smoother surface on stronger profiles, cheaper on Balanced
	local N = math.min(math.floor((Spec.Segments or 84) * math.clamp(E.Profile.Scale, 0.7, 1.15)), 120);
	local Bands = {};

	for BandIndex, B in ipairs(Spec.Bands) do
		local Bars = {};
		local Colors;

		if Spec.Top then
			Colors = ColorSequence.new({
				ColorSequenceKeypoint.new(0, B.Body), ColorSequenceKeypoint.new(0.86, B.Body), ColorSequenceKeypoint.new(1, B.Crest),
			});
		else
			Colors = ColorSequence.new({
				ColorSequenceKeypoint.new(0, B.Crest), ColorSequenceKeypoint.new(0.14, B.Body), ColorSequenceKeypoint.new(1, B.Body),
			});
		end;

		for I = 1, N do
			local Bar = self:New('Frame', {
				AnchorPoint = Spec.Top and Vector2.new(0, 0) or Vector2.new(0, 1);
				BackgroundColor3 = Color3.new(1, 1, 1);
				BackgroundTransparency = B.Alpha or 0;
				Position = UDim2.new((I - 1) / N, 0, Spec.Top and 0 or 1, 0);
				Size = UDim2.new(1 / N, 1, B.Height, 0);
			}, Layer);

			self:New('UIGradient', { Rotation = 90; Color = Colors; }, Bar);
			Bars[I] = Bar;
		end;

		Bands[BandIndex] = { Bars = Bars; B = B; Phase = (BandIndex - 1) * 1.7; };
	end;

	self:Tick(function(T)
		for _, Band in ipairs(Bands) do
			local B, Bars = Band.B, Band.Bars;
			local Speed = B.Speed or 0.8;

			for I = 1, N do
				local X = (I - 1) / N * 96;
				local H = B.Height
					+ math.sin(X * B.Freq + T * Speed * 2 + Band.Phase) * B.Amp
					+ math.sin(X * 0.17 - T * Speed * 1.2) * B.Amp * 0.55
					+ math.sin(X * 0.9 + T * 1.9 + Band.Phase) * B.Amp * 0.18;

				Bars[I].Size = UDim2.new(1 / N, 1, H, 0);
			end;
		end;
	end, LayerName);
end;

-- Soft rising smoke / haze: a stack of faint circles (there is no radial gradient, so many thin rings give the
-- soft edge). Puffs grow while they rise.
-- Spec: Layer, Count (budgeted), Size {min, max} px, Speed {min, max}, Color, Alpha (transparency of ONE ring), Rings
function RM:Smoke(Spec)
	local Count = self:Budget(Spec.Count or 6);
	if Count <= 0 then
		return;
	end;

	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Rings = Spec.Rings or 10;

	for _ = 1, Count do
		local Dur = 1.25 / Roll(Spec.Speed or { 0.02, 0.05 });
		local P0 = FXRandom:NextNumber();
		local S0 = Roll(Spec.Size or { 80, 130 });
		local X = FXRandom:NextNumber();

		local Mover = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Size = UDim2.fromOffset(0, 0);
		}, Layer);

		local Holder = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1;
			Position = UDim2.fromOffset(0, 0); Size = UDim2.fromOffset(S0 * 0.6, S0 * 0.6);
		}, Mover);

		for R = 0, Rings - 1 do
			local Scale = 1 - R * (0.85 / Rings);
			local Ring = self:New('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Color; BackgroundTransparency = Spec.Alpha or 0.93;
				Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromScale(Scale, Scale);
			}, Holder);
			Round(Ring, 0.5, 0);
		end;

		self:Cycle(Mover, { Position = { UDim2.fromScale(X, 1.05), UDim2.fromScale(X + Roll({ -0.06, 0.06 }), -0.2) } }, Dur, LayerName, P0);
		self:Cycle(Holder, { Size = { UDim2.fromOffset(S0 * 0.6, S0 * 0.6), UDim2.fromOffset(S0 * 2.1, S0 * 2.1) } }, Dur, LayerName, P0);
		self:Sway(Holder, { Position = { UDim2.fromOffset(-18, 0), UDim2.fromOffset(18, 0) } }, Roll({ 3, 5 }), LayerName);
	end;
end;

-- Dark triangular mountains / volcano cones: a 45-degree square whose center sits on the bottom edge.
-- Uses the window's pixel height, so scenes that call it set Pixel = true (rebuilt after a resize).
-- Spec: Layer, Items = { { X (scale), Height (fraction of the window height), Color, Alpha } }
function RM:Mountains(Spec)
	local H = self:Size().Y;
	local Layer = self.Layers[Spec.Layer or 'Atmosphere'];

	for _, M in ipairs(Spec.Items) do
		local Side = (M.Height * H) / 0.7071;

		self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = M.Color; BackgroundTransparency = M.Alpha or 0;
			Position = UDim2.new(M.X, 0, 1, 0); Rotation = 45; Size = UDim2.fromOffset(Side, Side);
		}, Layer);
	end;
end;

-- Synthwave sun: a circle cut into horizontal slices; the lower half gets thinner and thinner stripes.
-- Spec: Layer, X, Y (scale of the circle center), Size (px), Bars, Top, Bottom (Color3)
function RM:Sun(Spec)
	local Layer = self.Layers[Spec.Layer or 'Atmosphere'];
	local Size = self:Size();
	local D = Spec.Size;
	local R = D / 2;
	local K = Spec.Bars or 26;
	local CX, CY = Size.X * Spec.X, Size.Y * Spec.Y;

	for I = 0, K - 1 do
		local Y0 = I * D / K;
		local YC = Y0 + D / K / 2;
		local Half = math.sqrt(math.max(R * R - (YC - R) * (YC - R), 0));
		local T = I / K;
		local BarH = D / K;

		if T > 0.5 then
			BarH = BarH * (1 - (T - 0.5) * 2 * 0.78);
		end;

		self:New('Frame', {
			BackgroundColor3 = Spec.Top:Lerp(Spec.Bottom, T);
			Position = UDim2.fromOffset(CX - Half, CY - R + Y0); Size = UDim2.fromOffset(Half * 2, BarH);
		}, Layer);
	end;
end;

-- City silhouette with lit windows and a neon roof line (static).
-- Spec: Layer, Y (scale of the ground line), Color, Edge, Lights (list of Color3)
function RM:Skyline(Spec)
	local Layer = self.Layers[Spec.Layer or 'Atmosphere'];
	local Size = self:Size();
	local X = 0;

	while X < Size.X do
		local W = FXRandom:NextInteger(26, 56);
		local H = Roll({ 0.05, 0.2 }) * Size.Y;

		local Building = self:New('Frame', {
			BackgroundColor3 = Spec.Color; Position = UDim2.fromOffset(X, Size.Y * Spec.Y - H); Size = UDim2.fromOffset(W, H);
		}, Layer);

		self:New('Frame', { BackgroundColor3 = Spec.Edge; BackgroundTransparency = 0.3; Size = UDim2.new(1, 0, 0, 2); }, Building);

		for K = 1, math.floor(W * H / 260) do
			self:New('Frame', {
				BackgroundColor3 = Spec.Lights[(K - 1) % #Spec.Lights + 1]; BackgroundTransparency = 1 - Roll({ 0.3, 0.8 });
				Position = UDim2.fromOffset(Roll({ 3, W - 5 }), Roll({ 5, H - 4 })); Size = UDim2.fromOffset(2, 3);
			}, Building);
		end;

		X = X + W + FXRandom:NextInteger(0, 6);
	end;
end;

-- Schools of small fish swimming across; followers trail the leader.
-- Spec: Layer, Count (budgeted), Per (fish per school), Y {from, to}, Colors, Alpha (transparency)
function RM:Fish(Spec)
	local Total = self:Budget(Spec.Count or 12);
	if Total <= 0 then
		return;
	end;

	local LayerName = Spec.Layer or 'Decor';
	local Layer = self.Layers[LayerName];
	local Per = Spec.Per or 4;
	local Colors = Spec.Colors;
	local Made = 0;

	for School = 0, math.ceil(Total / Per) - 1 do
		local Dir = (School % 2 == 1) and -1 or 1;
		local Y = Roll(Spec.Y or { 0.35, 0.7 });
		local Dur = 1.3 / Roll(Spec.Speed or { 0.04, 0.07 });
		local P0 = FXRandom:NextNumber();

		for Slot = 0, Per - 1 do
			if Made >= Total then
				break;
			end;
			Made = Made + 1;

			local Color = Colors[(School + Slot) % #Colors + 1];
			local Size = Roll(Spec.Size or { 20, 28 });
			local FishY = Y + Roll({ -0.03, 0.03 });

			local Mover = self:New('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Size = UDim2.fromOffset(0, 0);
			}, Layer);

			local Holder = self:New('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1;
				Position = UDim2.fromOffset(0, 0); Size = UDim2.fromOffset(Size, Size * 0.45);
			}, Mover);

			local Body = self:New('Frame', {
				BackgroundColor3 = Color; BackgroundTransparency = Spec.Alpha or 0.22; Size = UDim2.fromScale(1, 1);
			}, Holder);
			Round(Body, 0.5, 0);

			local Tail = self:New('Frame', {
				AnchorPoint = Vector2.new(Dir > 0 and 0 or 1, 0); BackgroundColor3 = Color; BackgroundTransparency = Spec.Alpha or 0.22;
				Position = UDim2.new(Dir > 0 and 0 or 1, Dir > 0 and -Size * 0.22 or Size * 0.22, 0.12, 0); Rotation = 45;
				Size = UDim2.fromOffset(Size * 0.4, Size * 0.4);
			}, Holder);
			Round(Tail, 0, 2);

			local From, To = Dir > 0 and -0.15 or 1.15, Dir > 0 and 1.15 or -0.15;
			self:Cycle(Mover, { Position = { UDim2.fromScale(From, FishY), UDim2.fromScale(To, FishY) } }, Dur, LayerName, (P0 - Slot * 0.035) % 1);
			self:Sway(Holder, { Position = { UDim2.fromOffset(0, -6), UDim2.fromOffset(0, 6) } }, Roll({ 1, 1.8 }), LayerName);
			self:Sway(Holder, { Rotation = { -5, 5 } }, Roll({ 0.6, 1.1 }), LayerName);
		end;
	end;
end;

-- Swaying seaweed rooted on the bottom edge (Spec: Layer, Count, X {from, to}, Height {min, max} px, Color, Tip)
function RM:Kelp(Spec)
	local LayerName = Spec.Layer or 'Decor';
	local Layer = self.Layers[LayerName];
	local X = Spec.X or { 0.03, 0.97 };
	local Count = Spec.Count or 10;

	for I = 1, Count do
		local K = Count == 1 and 0.5 or (I - 1) / (Count - 1);

		local Pivot = self:New('Frame', {
			BackgroundTransparency = 1; Position = UDim2.new(X[1] + (X[2] - X[1]) * K + Roll({ -0.015, 0.015 }), 0, 1, 0); Size = UDim2.fromOffset(0, 0);
		}, Layer);

		local Blade = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 1); BackgroundColor3 = Color3.new(1, 1, 1);
			Position = UDim2.fromOffset(0, 0); Size = UDim2.fromOffset(8, Roll(Spec.Height or { 70, 140 }));
		}, Pivot);
		Round(Blade, 0, 4);
		self:New('UIGradient', { Rotation = 90; Color = ColorSequence.new(Spec.Tip, Spec.Color); }, Blade);

		self:Sway(Pivot, { Rotation = { -8, 8 } }, Roll({ 1.4, 2.6 }), LayerName);
	end;
end;

-- Expanding rings that fade as they grow (sonar / halo / ripples).
-- Spec: Layer, X, Y, Count, Min, Max (px), Period (s), Color, Alpha (opacity at the start), Thickness
function RM:Pulse(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Count = Spec.Count or 3;

	for I = 1, Count do
		local Ring = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1;
			Position = UDim2.fromScale(Spec.X, Spec.Y); Size = UDim2.fromOffset(Spec.Min, Spec.Min);
		}, Layer);
		Round(Ring, 0.5, 0);

		local Stroke = Instance.new('UIStroke');
		Stroke.Color = Spec.Color;
		Stroke.Thickness = Spec.Thickness or 2;
		Stroke.Transparency = 1;
		Stroke.Parent = Ring;

		local P0 = (I - 1) / Count;
		self:Cycle(Ring, { Size = { UDim2.fromOffset(Spec.Min, Spec.Min), UDim2.fromOffset(Spec.Max, Spec.Max) } }, Spec.Period, LayerName, P0);
		self:Cycle(Stroke, { Transparency = { 1 - (Spec.Alpha or 0.5), 1 } }, Spec.Period, LayerName, P0);
	end;
end;

-- Soft diagonal band of light (Milky Way). Spec: Layer, X, Y (scale), Width, Height (px), Rotation, Color, Alpha (max opacity)
function RM:Band(Spec)
	local Band = self:New('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Color; Position = UDim2.fromScale(Spec.X, Spec.Y);
		Rotation = Spec.Rotation or 0; Size = UDim2.fromOffset(Spec.Width, Spec.Height);
	}, self.Layers[Spec.Layer or 'Atmosphere']);

	self:New('UIGradient', { Rotation = 90; Transparency = NS(0, 1, 0.5, 1 - (Spec.Alpha or 0.3), 1, 1); }, Band);
end;

-- light shafts from the top (Spec: Count, Color, Width {px}, X {from,to}, Sway (degrees), Start (transparency at the top))
function RM:Rays(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local N = Spec.Count or 4;
	local X = Spec.X or { 0.1, 0.9 };
	local Sway = Spec.Sway or 4;

	for I = 1, N do
		local K = N == 1 and 0.5 or (I - 1) / (N - 1);
		local Base = (K - 0.5) * 24;

		local F = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0); BackgroundColor3 = Spec.Color; BackgroundTransparency = 0.05;
			Position = UDim2.fromScale(X[1] + (X[2] - X[1]) * K, -0.25); Rotation = Base;
			Size = UDim2.new(0, Roll(Spec.Width or { 30, 60 }), 1.7, 0);
		}, Layer);

		self:New('UIGradient', { Rotation = 90; Transparency = NS(0, Spec.Start or 0.8, 0.55, 0.93, 1, 1); }, F);

		self:Sway(F, { Rotation = { Base - Sway, Base + Sway } }, Roll({ 6, 11 }), LayerName);
		self:Sway(F, { BackgroundTransparency = { 0.05, 0.32 } }, Roll({ 2.5, 5 }), LayerName);
	end;
end;

-- drifting clouds (Spec: Count, Y {from,to}, Width {fraction of the window width}, Speed (scale/sec), Alpha (transparency), Color)
function RM:Clouds(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Size = self:Size();
	local Color = Spec.Color or Color3.new(1, 1, 1);
	local Alpha = Spec.Alpha or 0.84;

	for _ = 1, (Spec.Count or 3) do
		local W = Size.X * Roll(Spec.Width or { 0.2, 0.32 });
		local H = W * 0.42;
		local Y = Roll(Spec.Y or { 0.6, 0.9 });

		local Cloud = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Size = UDim2.fromOffset(W, H);
		}, Layer);

		local Base = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 1); BackgroundColor3 = Color; BackgroundTransparency = Alpha;
			Position = UDim2.fromScale(0.5, 1); Size = UDim2.fromScale(1, 0.5);
		}, Cloud);
		Round(Base, 0.5, 0);

		for _, Puff in ipairs({ { 0.3, 0.5, 0.62 }, { 0.55, 0.38, 0.8 }, { 0.78, 0.55, 0.52 } }) do
			local D = H * Puff[3];
			local P = self:New('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color; BackgroundTransparency = Alpha;
				Position = UDim2.fromScale(Puff[1], Puff[2]); Size = UDim2.fromOffset(D, D);
			}, Cloud);
			Round(P, 0.5, 0);
		end;

		self:Cycle(Cloud, { Position = { UDim2.fromScale(-0.25, Y), UDim2.fromScale(1.25, Y) } }, 1.5 / Roll(Spec.Speed or { 0.004, 0.01 }), LayerName);
	end;
end;

-- soft round glow: stacked translucent circles (Spec: Color, Size px, X, Y, Alpha = transparency of ONE ring, Rings,
-- Pulse {speed, amount}, Drift {ax, ay, speed})
function RM:Glow(Spec)
	local LayerName = Spec.Layer or 'Lighting';
	local Base = Spec.Size or 300;
	local Rings = Spec.Rings or 9;
	local X, Y = Spec.X or 0.5, Spec.Y or 0.5;

	local Holder = self:New('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1;
		Position = UDim2.fromScale(X, Y); Size = UDim2.fromOffset(Base, Base);
	}, self.Layers[LayerName]);

	for I = 1, Rings do
		local Scale = 1 - (I - 1) / Rings * 0.8;
		local Ring = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Color; BackgroundTransparency = Spec.Alpha or 0.965;
			Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromScale(Scale, Scale);
		}, Holder);
		Round(Ring, 0.5, 0);
	end;

	if Spec.Pulse then -- breathes between (1 - amount) and (1 + amount) of its size
		local Amount = Spec.Pulse[2];
		self:Sway(Holder, { Size = { UDim2.fromOffset(Base * (1 - Amount), Base * (1 - Amount)), UDim2.fromOffset(Base * (1 + Amount), Base * (1 + Amount)) } }, math.pi / Spec.Pulse[1], LayerName);
	end;

	if Spec.Drift then
		local AX, AY = Spec.Drift[1], Spec.Drift[2];
		self:Sway(Holder, { Position = { UDim2.fromScale(X - AX, Y - AY), UDim2.fromScale(X + AX, Y + AY) } }, math.pi / Spec.Drift[3], LayerName);
	end;
end;

-- horizontal scan line with a glowing trail (scripted: it needs a pause between sweeps)
function RM:Scanner(Spec)
	local LayerName = Spec.Layer or 'Lighting';
	local Bar = self:New('Frame', {
		BackgroundColor3 = Spec.Color; BackgroundTransparency = 0.2; Size = UDim2.new(1, 0, 0, 2); Visible = false;
	}, self.Layers[LayerName]);

	local Trail = self:New('Frame', {
		AnchorPoint = Vector2.new(0, 1); BackgroundColor3 = Spec.Color; Size = UDim2.new(1, 0, 0, 46);
	}, Bar);
	self:New('UIGradient', { Rotation = 90; Transparency = NS(0, 1, 1, 0.78); }, Trail);

	local Period, Phase = Spec.Period or 6, Spec.Phase or 0;

	self:Tick(function(T)
		local P = ((T + Phase) % Period) / Period;
		if P < 0.45 then
			Bar.Visible = true;
			Bar.Position = UDim2.fromScale(0, P / 0.45);
		else
			Bar.Visible = false;
		end;
	end, LayerName);
end;

-- darkened edges
function RM:Vignette(Spec)
	local Layer = self.Layers[Spec.Layer or 'Atmosphere'];
	local Strength = Spec.Strength or 0.5;

	for _, E in ipairs({
		{ Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.3), 90 };
		{ Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.3), 270 };
		{ Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.22, 1), 0 };
		{ Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.22, 1), 180 };
	}) do
		local F = self:New('Frame', {
			AnchorPoint = E[1]; BackgroundColor3 = Color3.new(0, 0, 0); Position = E[2]; Size = E[3];
		}, Layer);
		self:New('UIGradient', { Rotation = E[4]; Transparency = NS(0, 1 - Strength, 1, 1); }, F);
	end;
end;

-- perspective grid: converging lines + rows that scroll toward the viewer (Spec: Color, Horizon, Lines, Spread, Rows, Speed)
function RM:Grid(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Size = self:Size();
	local W, H = Size.X, Size.Y;
	local VX, VY = W * 0.5, H * (Spec.Horizon or 0.42);

	for I = -(Spec.Lines or 8), (Spec.Lines or 8) do
		local BX, BY = W * 0.5 + I * W * (Spec.Spread or 0.2), H * 1.08;
		local DX, DY = BX - VX, BY - VY;
		local Line = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Color;
			Position = UDim2.fromOffset((VX + BX) / 2, (VY + BY) / 2);
			Rotation = math.deg(math.atan2(-DX, DY));
			Size = UDim2.fromOffset(1.5, math.sqrt(DX * DX + DY * DY));
		}, Layer);
		self:New('UIGradient', { Rotation = 90; Transparency = NS(0, 1, 0.4, 0.65, 1, 0.15); }, Line);
	end;

	local Rows = Spec.Rows or 9;
	local Lines = {};
	for I = 1, Rows do
		Lines[I] = self:New('Frame', {
			AnchorPoint = Vector2.new(0, 0.5); BackgroundColor3 = Spec.Color; Size = UDim2.new(1, 0, 0, 1);
		}, Layer);
	end;

	local Speed = Spec.Speed or 0.08;

	self:Tick(function(T)
		for I = 1, Rows do
			local P = ((I / Rows) + T * Speed) % 1;
			local Curve = P ^ 2.2;
			Lines[I].Position = UDim2.fromOffset(0, VY + (H * 1.05 - VY) * Curve);
			Lines[I].Size = UDim2.new(1, 0, 0, 1 + Curve * 1.8);
			Lines[I].BackgroundTransparency = 1 - (0.1 + Curve * 0.7);
		end;
	end, LayerName);
end;

-- floating holographic panels with a scrolling "data" bar or two
function RM:HoloPanels(Spec)
	local LayerName = Spec.Layer or 'Decor';
	local Layer = self.Layers[LayerName];

	for _ = 1, (Spec.Count or 3) do
		local X = FXRandom:NextNumber() * 0.8;
		local Speed = 0.008 + FXRandom:NextNumber() * 0.01;

		local F = self:New('Frame', {
			BackgroundColor3 = Spec.Color; BackgroundTransparency = 0.95;
			Size = UDim2.fromScale(0.12 + FXRandom:NextNumber() * 0.08, 0.1 + FXRandom:NextNumber() * 0.08);
		}, Layer);
		Round(F, 0, 3);

		local Stroke = Instance.new('UIStroke');
		Stroke.Color = Spec.Color;
		Stroke.Thickness = 1;
		Stroke.Transparency = 0.72;
		Stroke.Parent = F;

		for K = 1, 3 do
			self:New('Frame', {
				BackgroundColor3 = Spec.Color; BackgroundTransparency = 0.75;
				Position = UDim2.new(0.1, 0, K * 0.22, 0); Size = UDim2.new(0.3 + FXRandom:NextNumber() * 0.5, 0, 0, 2);
			}, F);
		end;

		self:Cycle(F, { Position = { UDim2.fromScale(X, 1.1), UDim2.fromScale(X, -0.25) } }, 1.35 / Speed, LayerName);
		self:Sway(Stroke, { Transparency = { 0.55, 0.85 } }, Roll({ 0.8, 1.6 }), LayerName);
	end;
end;
-- ---------------------------------------------------------------- hero art
-- Every live theme has a hero figure behind the menu (a guardian, an angel, a ship, a kraken ...). It stays where it is and moves its joints.
-- Figures (and the emblems some accessories use) are lists of drawing commands. The store preview draws the very same lists as SVG, so the web preview and this
-- menu show the same art. A figure is drawn ONCE into a CanvasGroup (one texture, so moving / fading it is free).
--   c k                  colour slot of what follows: 1 lines / bright, 2 body, 3 light, 4 glow
--   l x1 y1 x2 y2 w a    line           p closed w a x y x y ...   polyline / polygon outline     f a x y x y ...   filled polygon
--   d x y r a            dot            e cx cy rx ry w a rot      ellipse outline                b cx cy rx ry a rot   filled ellipse
--   r r w a              ring at the centre
--   g id                 a new part starts (rigged figures: see Rigs, the parts are drawn in this order)
-- numbers are integers: coordinates and widths x1000 (1 = half the figure), opacity x100, angles x10
local Figures = {};
Figures.Guardian = [[
g base
g halo
c 3
e 0 -500 500 500 12 55 0
e 0 -500 420 420 8 35 0
c 1
l 540 -500 640 -500 18 85
c 3
l 522 -360 570 -347 8 50
c 1
l 468 -230 554 -180 18 85
c 3
l 382 -118 417 -83 8 50
c 1
l 270 -32 320 54 18 85
c 3
l 140 22 153 70 8 50
c 1
l 0 40 0 140 18 85
c 3
l -140 22 -153 70 8 50
c 1
l -270 -32 -320 54 18 85
c 3
l -382 -118 -417 -83 8 50
c 1
l -468 -230 -554 -180 18 85
c 3
l -522 -360 -570 -347 8 50
c 1
l -540 -500 -640 -500 18 85
c 3
l -522 -640 -570 -653 8 50
c 1
l -468 -770 -554 -820 18 85
c 3
l -382 -882 -417 -917 8 50
c 1
l -270 -968 -320 -1054 18 85
c 3
l -140 -1022 -153 -1070 8 50
c 1
l 0 -1040 0 -1140 18 85
c 3
l 140 -1022 153 -1070 8 50
c 1
l 270 -968 320 -1054 18 85
c 3
l 382 -882 417 -917 8 50
c 1
l 468 -770 554 -820 18 85
c 3
l 522 -640 570 -653 8 50
g rune
c 1
e 0 950 840 130 12 85 0
e 0 950 620 90 8 55 0
c 4
d 779 999 14 90
c 4
d 328 1070 14 90
c 4
d -315 1071 14 90
c 4
d -773 1001 14 90
c 4
d -779 901 14 90
c 4
d -328 830 14 90
c 4
d 315 829 14 90
c 4
d 773 899 14 90
g orbit
c 2
f 100 1015 72 940 81 879 36 954 27
c 1
p 1 10 90 1015 72 940 81 879 36 954 27
c 3
f 100 272 815 227 754 236 679 281 740
c 1
p 1 10 90 272 815 227 754 236 679 281 740
c 2
f 100 -742 542 -713 473 -644 444 -673 513
c 1
p 1 10 90 -742 542 -713 473 -644 444 -673 513
c 3
f 100 -1015 -472 -940 -481 -879 -436 -954 -427
c 1
p 1 10 90 -1015 -472 -940 -481 -879 -436 -954 -427
c 2
f 100 -272 -1215 -227 -1154 -236 -1079 -281 -1140
c 1
p 1 10 90 -272 -1215 -227 -1154 -236 -1079 -281 -1140
c 3
f 100 742 -942 713 -873 644 -844 673 -913
c 1
p 1 10 90 742 -942 713 -873 644 -844 673 -913
g wR1
c 1
l 200 -500 534 -635 101 100
l 534 -635 942 -800 61 100
c 2
l 200 -500 534 -635 75 100
l 534 -635 942 -800 38 100
c 4
l 534 -635 779 -734 8 90
g wR2
c 1
l 200 -500 474 -747 101 100
l 474 -747 809 -1049 61 100
c 2
l 200 -500 474 -747 75 100
l 474 -747 809 -1049 38 100
c 4
l 474 -747 675 -928 8 90
g wR3
c 1
l 200 -500 348 -778 96 100
l 348 -778 529 -1118 59 100
c 2
l 200 -500 348 -778 70 100
l 348 -778 529 -1118 35 100
c 4
l 348 -778 456 -982 8 90
g wR4
c 1
l 200 -500 241 -730 86 100
l 241 -730 290 -1012 53 100
c 2
l 200 -500 241 -730 60 100
l 241 -730 290 -1012 30 100
c 4
l 241 -730 270 -899 8 90
g wL1
c 1
l -200 -500 -534 -635 101 100
l -534 -635 -942 -800 61 100
c 2
l -200 -500 -534 -635 75 100
l -534 -635 -942 -800 38 100
c 4
l -534 -635 -779 -734 8 90
g wL2
c 1
l -200 -500 -474 -747 101 100
l -474 -747 -809 -1049 61 100
c 2
l -200 -500 -474 -747 75 100
l -474 -747 -809 -1049 38 100
c 4
l -474 -747 -675 -928 8 90
g wL3
c 1
l -200 -500 -348 -778 96 100
l -348 -778 -529 -1118 59 100
c 2
l -200 -500 -348 -778 70 100
l -348 -778 -529 -1118 35 100
c 4
l -348 -778 -456 -982 8 90
g wL4
c 1
l -200 -500 -241 -730 86 100
l -241 -730 -290 -1012 53 100
c 2
l -200 -500 -241 -730 60 100
l -241 -730 -290 -1012 30 100
c 4
l -241 -730 -270 -899 8 90
g legR
c 2
f 100 80 300 250 320 280 520 100 520
c 1
p 1 14 100 80 300 250 320 280 520 100 520
c 2
f 100 240 500 380 450 300 600 200 620
c 1
p 1 12 100 240 500 380 450 300 600 200 620
c 2
f 100 100 580 270 580 300 840 90 840
c 1
p 1 14 100 100 580 270 580 300 840 90 840
c 3
l 190 600 190 820 10 60
c 2
f 100 70 840 310 840 420 920 420 970 60 970 60 900
c 1
p 1 12 100 70 840 310 840 420 920 420 970 60 970 60 900
g legL
c 2
f 100 -80 300 -250 320 -280 520 -100 520
c 1
p 1 14 100 -80 300 -250 320 -280 520 -100 520
c 2
f 100 -240 500 -380 450 -300 600 -200 620
c 1
p 1 12 100 -240 500 -380 450 -300 600 -200 620
c 2
f 100 -100 580 -270 580 -300 840 -90 840
c 1
p 1 14 100 -100 580 -270 580 -300 840 -90 840
c 3
l -190 600 -190 820 10 60
c 2
f 100 -70 840 -310 840 -420 920 -420 970 -60 970 -60 900
c 1
p 1 12 100 -70 840 -310 840 -420 920 -420 970 -60 970 -60 900
g torso
c 2
f 100 -70 130 70 130 65 420 0 500 -65 420
c 1
p 1 12 100 -70 130 70 130 65 420 0 500 -65 420
c 2
f 100 90 130 200 130 240 380 140 450 90 400
c 1
p 1 12 100 90 130 200 130 240 380 140 450 90 400
c 2
f 100 -90 130 -200 130 -240 380 -140 450 -90 400
c 1
p 1 12 100 -90 130 -200 130 -240 380 -140 450 -90 400
c 2
f 100 -170 50 170 50 180 140 -180 140
c 1
p 1 12 100 -170 50 170 50 180 140 -180 140
c 4
d 0 95 30 100
c 2
f 100 0 -500 100 -500 220 -440 250 -340 210 -200 160 -80 140 20 150 60 0 60 -150 60 -140 20 -160 -80 -210 -200 -250 -340 -220 -440 -100 -500
c 1
p 1 16 100 0 -500 100 -500 220 -440 250 -340 210 -200 160 -80 140 20 150 60 0 60 -150 60 -140 20 -160 -80 -210 -200 -250 -340 -220 -440 -100 -500
c 3
l 10 -460 200 -400 8 50
l 40 -120 130 -150 8 40
l -10 -460 -200 -400 8 50
l -40 -120 -130 -150 8 40
c 1
p 0 18 95 -130 -150 0 -70 130 -150
p 0 12 60 -120 -40 0 40 120 -40
g core
c 2
f 100 0 -390 65 -300 0 -210 -65 -300
c 4
f 100 0 -370 45 -300 0 -230 -45 -300
c 1
e 0 -300 90 90 8 80 0
g neck
c 2
f 100 -90 -550 90 -550 120 -490 -120 -490
c 1
p 1 12 100 -90 -550 90 -550 120 -490 -120 -490
g finR
c 2
f 100 120 -800 190 -850 310 -990 270 -820 200 -760 130 -740
c 1
p 1 12 100 120 -800 190 -850 310 -990 270 -820 200 -760 130 -740
g finL
c 2
f 100 -120 -800 -190 -850 -310 -990 -270 -820 -200 -760 -130 -740
c 1
p 1 12 100 -120 -800 -190 -850 -310 -990 -270 -820 -200 -760 -130 -740
g helm
c 2
f 100 0 -880 70 -870 120 -820 135 -740 130 -660 100 -600 50 -550 0 -540 -50 -550 -100 -600 -130 -660 -135 -740 -120 -820 -70 -870
c 1
p 1 16 100 0 -880 70 -870 120 -820 135 -740 130 -660 100 -600 50 -550 0 -540 -50 -550 -100 -600 -130 -660 -135 -740 -120 -820 -70 -870
c 2
f 100 -40 -880 40 -880 55 -960 0 -1050 -55 -960
c 1
p 1 12 100 -40 -880 40 -880 55 -960 0 -1050 -55 -960
c 1
l 0 -870 0 -730 12 90
c 1
l -50 -640 50 -640 8 60
l -40 -610 40 -610 8 60
l -30 -580 30 -580 8 60
g visor
c 4
f 100 -105 -725 105 -725 88 -688 -88 -688
g uarmR
c 2
f 100 400 -360 550 -360 520 -20 370 -20
c 1
p 1 14 100 400 -360 550 -360 520 -20 370 -20
g farmR
c 2
f 100 330 -40 490 0 640 -60 640 -170 550 -150 420 -100
c 1
p 1 14 100 330 -40 490 0 640 -60 640 -170 550 -150 420 -100
c 1
d 430 0 35 100
g pauldR
c 2
f 100 120 -500 200 -580 340 -620 480 -580 630 -720 570 -500 530 -400 400 -360 260 -380 140 -440
c 1
p 1 16 100 120 -500 200 -580 340 -620 480 -580 630 -720 570 -500 530 -400 400 -360 260 -380 140 -440
c 2
f 100 250 -380 400 -360 530 -400 500 -270 400 -210 280 -250
c 1
p 1 12 100 250 -380 400 -360 530 -400 500 -270 400 -210 280 -250
c 3
p 0 10 80 200 -570 340 -610 470 -570
c 4
d 630 -720 20 100
g pauldL
c 2
f 100 -120 -500 -200 -580 -340 -620 -480 -580 -630 -720 -570 -500 -530 -400 -400 -360 -260 -380 -140 -440
c 1
p 1 16 100 -120 -500 -200 -580 -340 -620 -480 -580 -630 -720 -570 -500 -530 -400 -400 -360 -260 -380 -140 -440
c 2
f 100 -250 -380 -400 -360 -530 -400 -500 -270 -400 -210 -280 -250
c 1
p 1 12 100 -250 -380 -400 -360 -530 -400 -500 -270 -400 -210 -280 -250
c 3
p 0 10 80 -200 -570 -340 -610 -470 -570
c 4
d -630 -720 20 100
g sword
c 2
f 100 584 -220 656 -220 650 -800 620 -1020 590 -800
c 1
p 1 12 100 584 -220 590 -800 620 -1020 650 -800 656 -220
c 4
l 620 -250 620 -920 12 100
c 1
l 460 -200 780 -200 28 100
l 460 -200 430 -270 18 100
l 780 -200 810 -270 18 100
c 2
l 620 -170 620 0 30 100
c 1
d 620 30 30 100
c 2
b 620 -100 55 65 100 0
c 1
e 620 -100 55 65 12 95 0
g shield
c 2
f 100 -940 -470 -680 -530 -420 -470 -400 -100 -460 240 -680 660 -900 240 -960 -100
c 1
p 1 30 100 -940 -470 -680 -530 -420 -470 -400 -100 -460 240 -680 660 -900 240 -960 -100
c 3
p 1 10 60 -893 -387 -680 -437 -467 -387 -450 -76 -500 210 -680 562 -860 210 -910 -76
c 1
p 0 30 95 -860 -300 -680 -130 -500 -300
p 0 23 80 -860 -150 -680 20 -500 -150
p 0 16 65 -860 0 -680 170 -500 0
c 3
l -680 -500 -680 600 8 40
c 4
f 100 -680 -440 -620 -380 -680 -320 -740 -380
]];
Figures.Angel = [[
g base
g wingRo
c 3
b 160 -744 50 290 100 120
c 1
e 160 -744 50 290 8 75 120
c 3
b 253 -775 56 350 100 260
c 1
e 253 -775 56 350 8 75 260
c 3
b 357 -766 60 400 100 400
c 1
e 357 -766 60 400 8 75 400
c 3
b 456 -719 62 440 100 540
c 1
e 456 -719 62 440 8 75 540
c 3
b 527 -632 62 460 100 680
c 1
e 527 -632 62 460 8 75 680
c 3
b 546 -523 60 450 100 820
c 1
e 546 -523 60 450 8 75 820
c 3
b 508 -417 58 410 100 960
c 1
e 508 -417 58 410 8 75 960
c 3
b 429 -340 56 350 100 1100
c 1
e 429 -340 56 350 8 75 1100
c 3
b 332 -303 50 280 100 1240
c 1
e 332 -303 50 280 8 75 1240
g wingR
c 2
b 153 -622 45 170 100 180
c 1
e 153 -622 45 170 8 55 180
c 2
b 229 -651 50 230 100 340
c 1
e 229 -651 50 230 8 55 340
c 2
b 307 -634 52 270 100 500
c 1
e 307 -634 52 270 8 55 500
c 2
b 374 -582 54 300 100 660
c 1
e 374 -582 54 300 8 55 660
c 2
b 386 -505 54 290 100 810
c 1
e 386 -505 54 290 8 55 810
c 2
b 359 -433 52 260 100 960
c 1
e 359 -433 52 260 8 55 960
c 2
b 307 -385 50 220 100 1100
c 1
e 307 -385 50 220 8 55 1100
c 3
d 72 -618 32 100
c 3
d 83 -699 32 100
c 3
d 111 -780 32 100
c 3
d 156 -856 32 100
c 3
d 216 -926 32 100
c 3
d 292 -986 32 100
g wingLo
c 3
b -160 -744 50 290 100 3480
c 1
e -160 -744 50 290 8 75 3480
c 3
b -253 -775 56 350 100 3340
c 1
e -253 -775 56 350 8 75 3340
c 3
b -357 -766 60 400 100 3200
c 1
e -357 -766 60 400 8 75 3200
c 3
b -456 -719 62 440 100 3060
c 1
e -456 -719 62 440 8 75 3060
c 3
b -527 -632 62 460 100 2920
c 1
e -527 -632 62 460 8 75 2920
c 3
b -546 -523 60 450 100 2780
c 1
e -546 -523 60 450 8 75 2780
c 3
b -508 -417 58 410 100 2640
c 1
e -508 -417 58 410 8 75 2640
c 3
b -429 -340 56 350 100 2500
c 1
e -429 -340 56 350 8 75 2500
c 3
b -332 -303 50 280 100 2360
c 1
e -332 -303 50 280 8 75 2360
g wingL
c 2
b -153 -622 45 170 100 3420
c 1
e -153 -622 45 170 8 55 3420
c 2
b -229 -651 50 230 100 3260
c 1
e -229 -651 50 230 8 55 3260
c 2
b -307 -634 52 270 100 3100
c 1
e -307 -634 52 270 8 55 3100
c 2
b -374 -582 54 300 100 2940
c 1
e -374 -582 54 300 8 55 2940
c 2
b -386 -505 54 290 100 2790
c 1
e -386 -505 54 290 8 55 2790
c 2
b -359 -433 52 260 100 2640
c 1
e -359 -433 52 260 8 55 2640
c 2
b -307 -385 50 220 100 2500
c 1
e -307 -385 50 220 8 55 2500
c 3
d -72 -618 32 100
c 3
d -83 -699 32 100
c 3
d -111 -780 32 100
c 3
d -156 -856 32 100
c 3
d -216 -926 32 100
c 3
d -292 -986 32 100
g cloudSideL
c 3
b -720 980 200 70 80 0
b -820 930 100 70 80 0
b -620 920 120 80 80 0
c 2
b -720 1030 180 30 30 0
g cloudSideR
c 3
b 740 960 200 70 80 0
b 640 910 100 70 80 0
b 840 920 120 80 80 0
c 2
b 740 1010 180 30 30 0
g cloud
c 2
b 0 1060 560 70 35 0
c 3
b 0 1000 580 120 97 0
b -400 940 200 140 97 0
b -160 890 220 160 97 0
b 170 900 210 150 97 0
b 420 950 190 130 97 0
b -550 1000 140 90 97 0
b 560 1000 140 90 97 0
c 1
e -400 940 200 140 6 28 0
e -160 890 220 160 6 28 0
e 170 900 210 150 6 28 0
e 420 950 190 130 6 28 0
g mist
c 3
b -300 1080 300 50 40 0
b 250 1100 350 50 35 0
g robe
c 2
f 100 0 -620 60 -610 100 -560 100 -440 70 -300 90 -160 160 60 260 340 350 620 430 880 320 940 220 890 120 950 0 910 -120 950 -220 890 -320 940 -430 880 -350 620 -260 340 -160 60 -90 -160 -70 -300 -100 -440 -100 -560 -60 -610
c 1
p 1 14 95 0 -620 60 -610 100 -560 100 -440 70 -300 90 -160 160 60 260 340 350 620 430 880 320 940 220 890 120 950 0 910 -120 950 -220 890 -320 940 -430 880 -350 620 -260 340 -160 60 -90 -160 -70 -300 -100 -440 -100 -560 -60 -610
c 3
p 0 8 50 50 -100 90 400 140 860
p 0 8 50 -50 -100 -90 400 -140 860
p 0 8 50 100 100 180 500 280 860
p 0 8 50 -100 100 -180 500 -280 860
p 0 8 50 140 160 264 520 420 840
p 0 8 50 -140 160 -264 520 -420 840
c 4
p 0 20 95 -100 -300 -40 -270 40 -300 100 -270
g torso
g sleeveR
c 2
f 100 80 -600 200 -580 360 -400 440 -260 500 -200 400 -160 300 -260 200 -360 100 -440
c 1
p 1 12 90 80 -600 200 -580 360 -400 440 -260 500 -200 400 -160 300 -260 200 -360 100 -440
c 3
b 460 -200 34 45 100 200
g sleeveL
c 2
f 100 -80 -600 -200 -580 -360 -400 -440 -260 -500 -200 -400 -160 -300 -260 -200 -360 -100 -440
c 1
p 1 12 90 -80 -600 -200 -580 -360 -400 -440 -260 -500 -200 -400 -160 -300 -260 -200 -360 -100 -440
c 3
b -460 -200 34 45 100 -200
g light
c 4
d 480 -260 60 95
c 1
e 480 -260 90 90 8 70 0
g hair
c 4
f 95 0 -850 60 -840 100 -780 120 -680 130 -560 150 -420 120 -320 80 -400 70 -580 0 -600 -70 -580 -80 -400 -120 -320 -150 -420 -130 -560 -120 -680 -100 -780 -60 -840
g head
c 3
b 0 -720 66 78 100 0
c 1
e 0 -720 66 78 10 90 0
c 1
l -32 -725 -12 -718 8 90
l 12 -718 32 -725 8 90
c 1
l 0 -700 0 -690 8 80
g halo
c 4
e 0 -890 130 34 16 100 0
c 3
e 0 -890 130 34 6 70 0
g sparkles
c 4
p 1 10 100 -620 -895 -605 -855 -565 -840 -605 -825 -620 -785 -635 -825 -675 -840 -635 -855
c 4
p 1 10 100 660 -920 671 -891 700 -880 671 -869 660 -840 649 -869 620 -880 649 -891
c 4
p 1 10 100 -800 -355 -785 -315 -745 -300 -785 -285 -800 -245 -815 -285 -855 -300 -815 -315
c 4
p 1 10 100 820 -240 831 -211 860 -200 831 -189 820 -160 809 -189 780 -200 809 -211
c 4
p 1 10 100 -500 145 -485 185 -445 200 -485 215 -500 255 -515 215 -555 200 -515 185
c 4
p 1 10 100 600 260 611 289 640 300 611 311 600 340 589 311 560 300 589 289
c 4
p 1 10 100 0 -1055 15 -1015 55 -1000 15 -985 0 -945 -15 -985 -55 -1000 -15 -1015
]];
Figures.Ship = [[
g base
g mizzen
c 3
f 100 500 -580 880 100 500 120
c 1
p 1 12 90 500 -580 880 100 500 120
g jib
c 3
f 100 -970 40 -520 -620 -540 120
c 1
p 1 12 90 -970 40 -520 -620 -540 120
g foreSails
c 3
f 100 -760 -500 -240 -500 -253 -350 -261 -200 -341 -170 -420 -148 -500 -140 -580 -148 -659 -170 -739 -200 -747 -350
c 1
p 1 12 90 -760 -500 -240 -500 -253 -350 -261 -200 -341 -170 -420 -148 -500 -140 -580 -148 -659 -170 -739 -200 -747 -350
c 1
p 0 6 30 -630 -500 -609 -158
p 0 6 30 -370 -500 -391 -158
c 3
f 100 -670 -700 -330 -700 -338 -615 -344 -530 -396 -520 -448 -513 -500 -510 -552 -513 -604 -520 -656 -530 -661 -615
c 1
p 1 12 90 -670 -700 -330 -700 -338 -615 -344 -530 -396 -520 -448 -513 -500 -510 -552 -513 -604 -520 -656 -530 -661 -615
c 1
p 0 6 30 -585 -700 -571 -516
p 0 6 30 -415 -700 -429 -516
g mainSails
c 3
f 100 -400 -820 400 -820 380 -670 368 -520 245 -490 123 -468 0 -460 -123 -468 -245 -490 -368 -520 -380 -670
c 1
p 1 12 90 -400 -820 400 -820 380 -670 368 -520 245 -490 123 -468 0 -460 -123 -468 -245 -490 -368 -520 -380 -670
c 1
p 0 6 30 -200 -820 -168 -478
p 0 6 30 200 -820 168 -478
c 3
f 100 -460 -440 460 -440 437 -260 423 -80 282 -40 141 -11 0 0 -141 -11 -282 -40 -423 -80 -437 -260
c 1
p 1 12 90 -460 -440 460 -440 437 -260 423 -80 282 -40 141 -11 0 0 -141 -11 -282 -40 -423 -80 -437 -260
c 1
p 0 6 30 -230 -440 -193 -24
p 0 6 30 230 -440 193 -24
c 3
f 100 -300 -940 300 -940 285 -890 276 -840 184 -835 92 -831 0 -830 -92 -831 -184 -835 -276 -840 -285 -890
c 1
p 1 12 90 -300 -940 300 -940 285 -890 276 -840 184 -835 92 -831 0 -830 -92 -831 -184 -835 -276 -840 -285 -890
c 1
p 0 6 30 -150 -940 -126 -833
p 0 6 30 150 -940 126 -833
g sigil
c 4
e 0 -270 120 120 14 100 0
l 0 -400 0 -140 12 100
l -100 -300 100 -300 12 100
p 0 12 100 -100 -200 -56 -166 0 -140 56 -166 100 -200
g masts
c 1
l -500 200 -500 -720 24 100
l 0 200 0 -970 28 100
l 500 200 500 -600 22 100
c 1
l -780 -500 -220 -500 16 100
l -700 -700 -300 -700 12 100
l -440 -820 440 -820 16 100
l -500 -440 500 -440 16 100
l -340 -940 340 -940 12 100
c 2
f 100 -70 -640 70 -640 90 -560 -90 -560
c 1
p 1 12 100 -70 -640 70 -640 90 -560 -90 -560
c 1
l 0 -920 -970 40 7 50
l 0 -920 840 120 7 50
l -500 -700 -880 100 7 50
l 500 -600 840 100 7 45
l 0 -500 -160 200 6 40
l 0 -100 -120 200 6 40
l 0 -500 160 200 6 40
l 0 -100 120 200 6 40
g pennantA
c 4
f 100 0 -990 220 -950 0 -900
g pennantB
c 4
f 100 -500 -720 -300 -680 -500 -640
g hull
c 2
f 100 -860 140 -820 300 -600 520 -300 640 200 660 580 580 780 420 860 200 860 -60 640 -20 520 120 -200 180 -640 160
c 1
p 1 20 100 -860 140 -820 300 -600 520 -300 640 200 660 580 580 780 420 860 200 860 -60 640 -20 520 120 -200 180 -640 160
c 3
p 0 10 60 -800 260 -550 360 0 400 500 360 820 240
c 1
p 0 8 50 -700 400 -300 500 200 520 700 400
c 1
l -840 160 -970 30 22 100
p 0 14 90 -860 300 -891 274 -920 240 -900 180
g lamps
c 4
f 100 -620 290 -560 290 -560 340 -620 340
c 4
f 100 -480 290 -420 290 -420 340 -480 340
c 4
f 100 -340 290 -280 290 -280 340 -340 340
c 4
f 100 -200 290 -140 290 -140 340 -200 340
c 4
f 100 -60 290 0 290 0 340 -60 340
c 4
f 100 80 290 140 290 140 340 80 340
c 4
f 100 220 290 280 290 280 340 220 340
c 4
f 100 674 40 726 40 726 100 674 100
c 4
f 100 754 40 806 40 806 100 754 100
c 4
d 860 -100 30 100
d -860 100 26 100
g sea1
c 1
p 0 16 95 -1100 720 -1040 731 -963 743 -894 748 -825 749 -756 743 -687 733 -618 720 -550 707 -482 697 -413 691 -344 692 -275 697 -229 704 -183 712 -137 721 -68 734 0 744 68 749 137 749 206 742 275 732 321 724 367 714 413 706 482 697 550 691 619 692 688 697 757 708 825 721 893 734 962 744 1040 748 1100 749
g sea2
c 3
p 0 12 70 -1100 852 -1040 842 -963 828 -917 818 -871 808 -825 799 -756 789 -687 785 -618 789 -550 798 -504 807 -459 818 -413 828 -344 841 -275 851 -206 854 -137 852 -68 842 0 828 46 818 91 807 137 798 206 789 275 785 344 789 413 798 459 807 504 818 550 828 596 837 642 846 688 852 757 855 825 851 893 841 962 827 1013 817 1064 806 1100 798
g sea3
c 1
p 0 12 55 -1100 897 -1040 893 -963 891 -894 897 -825 906 -779 914 -733 924 -687 932 -618 942 -550 949 -482 949 -413 944 -344 934 -275 921 -229 912 -183 904 -137 897 -68 891 0 891 68 897 137 907 183 915 229 925 275 933 344 943 413 949 482 949 550 944 596 937 642 929 688 920 757 907 825 897 893 892 962 891 1040 899 1100 907
g foam
c 3
d -800 700 16 85
c 3
d -500 740 16 85
c 3
d -200 700 16 85
c 3
d 100 740 16 85
c 3
d 400 700 16 85
c 3
d 700 740 16 85
c 3
p 0 10 70 -950 620 -904 643 -840 660 -790 651 -737 633 -700 620
]];
Figures.Kraken = [[
g base
g aR0_3
c 1
l 810 -610 780 -660 33 100
c 1
l 780 -660 718 -679 46 100
c 1
l 718 -679 660 -660 43 100
c 1
l 660 -660 643 -610 39 100
c 1
l 643 -610 640 -560 20 100
c 2
l 810 -610 780 -660 25 100
c 2
l 780 -660 718 -679 22 100
c 2
l 718 -679 660 -660 19 100
c 2
l 660 -660 643 -610 15 100
c 2
l 643 -610 640 -560 12 100
c 3
d 810 -610 10 85
c 3
d 718 -679 10 85
c 3
d 643 -610 10 85
g aR0_2
c 1
l 760 -200 799 -287 50 100
c 1
l 799 -287 827 -377 63 100
c 1
l 827 -377 840 -460 59 100
c 1
l 840 -460 833 -539 56 100
c 1
l 833 -539 810 -610 37 100
c 2
l 760 -200 799 -287 42 100
c 2
l 799 -287 827 -377 39 100
c 2
l 827 -377 840 -460 35 100
c 2
l 840 -460 833 -539 32 100
c 2
l 833 -539 810 -610 29 100
c 3
d 799 -287 12 85
c 3
d 840 -460 10 85
g aR0_1
c 1
l 504 90 580 40 66 100
c 1
l 580 40 632 -10 79 100
c 1
l 632 -10 680 -70 76 100
c 1
l 680 -70 723 -135 72 100
c 1
l 723 -135 760 -200 53 100
c 2
l 504 90 580 40 58 100
c 2
l 580 40 632 -10 55 100
c 2
l 632 -10 680 -70 52 100
c 2
l 680 -70 723 -135 48 100
c 2
l 723 -135 760 -200 45 100
c 3
d 504 90 19 85
c 3
d 632 -10 17 85
c 3
d 723 -135 14 85
g aR0_0
c 1
l 120 60 176 87 83 100
c 1
l 176 87 257 124 96 100
c 1
l 257 124 340 140 92 100
c 1
l 340 140 421 125 89 100
c 1
l 421 125 504 90 70 100
c 2
l 120 60 176 87 75 100
c 2
l 176 87 257 124 72 100
c 2
l 257 124 340 140 68 100
c 2
l 340 140 421 125 65 100
c 2
l 421 125 504 90 62 100
c 3
d 176 87 23 85
c 3
d 340 140 21 85
g aR1_3
c 1
l 900 300 871 236 34 100
c 1
l 871 236 820 200 45 100
c 1
l 820 200 765 224 41 100
c 1
l 765 224 720 260 20 100
c 2
l 900 300 871 236 26 100
c 2
l 871 236 820 200 21 100
c 2
l 820 200 765 224 17 100
c 2
l 765 224 720 260 12 100
c 3
d 900 300 10 85
c 3
d 820 200 10 85
g aR1_2
c 1
l 640 540 737 514 52 100
c 1
l 737 514 820 460 63 100
c 1
l 820 460 876 381 59 100
c 1
l 876 381 900 300 38 100
c 2
l 640 540 737 514 44 100
c 2
l 737 514 820 460 39 100
c 2
l 820 460 876 381 35 100
c 2
l 876 381 900 300 30 100
c 3
d 640 540 14 85
c 3
d 820 460 11 85
g aR1_1
c 1
l 318 366 378 430 75 100
c 1
l 378 430 440 480 86 100
c 1
l 440 480 506 514 82 100
c 1
l 506 514 574 535 77 100
c 1
l 574 535 640 540 57 100
c 2
l 318 366 378 430 67 100
c 2
l 378 430 440 480 62 100
c 2
l 440 480 506 514 58 100
c 2
l 506 514 574 535 53 100
c 2
l 574 535 640 540 49 100
c 3
d 378 430 20 85
c 3
d 506 514 17 85
g aR1_0
c 1
l 100 100 141 153 93 100
c 1
l 141 153 199 227 104 100
c 1
l 199 227 260 300 100 100
c 1
l 260 300 318 366 79 100
c 2
l 100 100 141 153 85 100
c 2
l 141 153 199 227 80 100
c 2
l 199 227 260 300 76 100
c 2
l 260 300 318 366 71 100
c 3
d 141 153 26 85
c 3
d 260 300 23 85
g aR2_3
c 1
l 730 790 800 740 34 100
c 1
l 800 740 835 677 45 100
c 1
l 835 677 840 620 41 100
c 1
l 840 620 760 580 20 100
c 2
l 730 790 800 740 26 100
c 2
l 800 740 835 677 21 100
c 2
l 835 677 840 620 17 100
c 2
l 840 620 760 580 12 100
c 3
d 730 790 10 85
c 3
d 835 677 10 85
g aR2_2
c 1
l 440 780 506 807 52 100
c 1
l 506 807 575 820 63 100
c 1
l 575 820 640 820 59 100
c 1
l 640 820 730 790 38 100
c 2
l 440 780 506 807 44 100
c 2
l 506 807 575 820 39 100
c 2
l 575 820 640 820 35 100
c 2
l 640 820 730 790 30 100
c 3
d 440 780 14 85
c 3
d 575 820 11 85
g aR2_1
c 1
l 201 464 231 547 75 100
c 1
l 231 547 270 620 86 100
c 1
l 270 620 320 684 82 100
c 1
l 320 684 379 739 77 100
c 1
l 379 739 440 780 57 100
c 2
l 201 464 231 547 67 100
c 2
l 231 547 270 620 62 100
c 2
l 270 620 320 684 58 100
c 2
l 320 684 379 739 53 100
c 2
l 379 739 440 780 49 100
c 3
d 231 547 20 85
c 3
d 320 684 17 85
g aR2_0
c 1
l 70 120 96 188 93 100
c 1
l 96 188 133 285 104 100
c 1
l 133 285 170 380 100 100
c 1
l 170 380 201 464 79 100
c 2
l 70 120 96 188 85 100
c 2
l 96 188 133 285 80 100
c 2
l 133 285 170 380 76 100
c 2
l 170 380 201 464 71 100
c 3
d 96 188 26 85
c 3
d 170 380 23 85
g aR3_3
c 1
l 479 931 540 900 35 100
c 1
l 540 900 564 849 46 100
c 1
l 564 849 560 800 41 100
c 1
l 560 800 480 780 20 100
c 2
l 479 931 540 900 27 100
c 2
l 540 900 564 849 22 100
c 2
l 564 849 560 800 17 100
c 2
l 560 800 480 780 12 100
c 3
d 540 900 10 85
c 3
d 560 800 10 85
g aR3_2
c 1
l 194 804 240 860 54 100
c 1
l 240 860 319 915 65 100
c 1
l 319 915 400 940 60 100
c 1
l 400 940 479 931 39 100
c 2
l 194 804 240 860 46 100
c 2
l 240 860 319 915 41 100
c 2
l 319 915 400 940 36 100
c 2
l 400 940 479 931 31 100
c 3
d 240 860 13 85
c 3
d 400 940 10 85
g aR3_1
c 1
l 83 505 97 585 74 100
c 1
l 97 585 120 660 85 100
c 1
l 120 660 153 734 80 100
c 1
l 153 734 194 804 59 100
c 2
l 83 505 97 585 66 100
c 2
l 97 585 120 660 61 100
c 2
l 120 660 153 734 56 100
c 2
l 153 734 194 804 51 100
c 3
d 97 585 19 85
c 3
d 153 734 16 85
g aR3_0
c 1
l 40 130 47 207 93 100
c 1
l 47 207 57 316 104 100
c 1
l 57 316 70 420 99 100
c 1
l 70 420 83 505 78 100
c 2
l 40 130 47 207 85 100
c 2
l 47 207 57 316 80 100
c 2
l 57 316 70 420 75 100
c 2
l 70 420 83 505 70 100
c 3
d 47 207 26 85
c 3
d 70 420 23 85
g aL0_3
c 1
l -810 -610 -780 -660 33 100
c 1
l -780 -660 -717 -679 46 100
c 1
l -717 -679 -660 -660 43 100
c 1
l -660 -660 -642 -610 39 100
c 1
l -642 -610 -640 -560 20 100
c 2
l -810 -610 -780 -660 25 100
c 2
l -780 -660 -717 -679 22 100
c 2
l -717 -679 -660 -660 19 100
c 2
l -660 -660 -642 -610 15 100
c 2
l -642 -610 -640 -560 12 100
c 3
d -810 -610 10 85
c 3
d -717 -679 10 85
c 3
d -642 -610 10 85
g aL0_2
c 1
l -760 -200 -799 -287 50 100
c 1
l -799 -287 -827 -377 63 100
c 1
l -827 -377 -840 -460 59 100
c 1
l -840 -460 -833 -539 56 100
c 1
l -833 -539 -810 -610 37 100
c 2
l -760 -200 -799 -287 42 100
c 2
l -799 -287 -827 -377 39 100
c 2
l -827 -377 -840 -460 35 100
c 2
l -840 -460 -833 -539 32 100
c 2
l -833 -539 -810 -610 29 100
c 3
d -799 -287 12 85
c 3
d -840 -460 10 85
g aL0_1
c 1
l -504 90 -580 40 66 100
c 1
l -580 40 -632 -10 79 100
c 1
l -632 -10 -680 -70 76 100
c 1
l -680 -70 -723 -135 72 100
c 1
l -723 -135 -760 -200 53 100
c 2
l -504 90 -580 40 58 100
c 2
l -580 40 -632 -10 55 100
c 2
l -632 -10 -680 -70 52 100
c 2
l -680 -70 -723 -135 48 100
c 2
l -723 -135 -760 -200 45 100
c 3
d -504 90 19 85
c 3
d -632 -10 17 85
c 3
d -723 -135 14 85
g aL0_0
c 1
l -120 60 -176 87 83 100
c 1
l -176 87 -257 124 96 100
c 1
l -257 124 -340 140 92 100
c 1
l -340 140 -421 125 89 100
c 1
l -421 125 -504 90 70 100
c 2
l -120 60 -176 87 75 100
c 2
l -176 87 -257 124 72 100
c 2
l -257 124 -340 140 68 100
c 2
l -340 140 -421 125 65 100
c 2
l -421 125 -504 90 62 100
c 3
d -176 87 23 85
c 3
d -340 140 21 85
g aL1_3
c 1
l -900 300 -871 236 34 100
c 1
l -871 236 -820 200 45 100
c 1
l -820 200 -765 224 41 100
c 1
l -765 224 -720 260 20 100
c 2
l -900 300 -871 236 26 100
c 2
l -871 236 -820 200 21 100
c 2
l -820 200 -765 224 17 100
c 2
l -765 224 -720 260 12 100
c 3
d -900 300 10 85
c 3
d -820 200 10 85
g aL1_2
c 1
l -640 540 -737 514 52 100
c 1
l -737 514 -820 460 63 100
c 1
l -820 460 -876 381 59 100
c 1
l -876 381 -900 300 38 100
c 2
l -640 540 -737 514 44 100
c 2
l -737 514 -820 460 39 100
c 2
l -820 460 -876 381 35 100
c 2
l -876 381 -900 300 30 100
c 3
d -640 540 14 85
c 3
d -820 460 11 85
g aL1_1
c 1
l -318 366 -378 430 75 100
c 1
l -378 430 -440 480 86 100
c 1
l -440 480 -506 514 82 100
c 1
l -506 514 -574 535 77 100
c 1
l -574 535 -640 540 57 100
c 2
l -318 366 -378 430 67 100
c 2
l -378 430 -440 480 62 100
c 2
l -440 480 -506 514 58 100
c 2
l -506 514 -574 535 53 100
c 2
l -574 535 -640 540 49 100
c 3
d -378 430 20 85
c 3
d -506 514 17 85
g aL1_0
c 1
l -100 100 -141 153 93 100
c 1
l -141 153 -199 227 104 100
c 1
l -199 227 -260 300 100 100
c 1
l -260 300 -318 366 79 100
c 2
l -100 100 -141 153 85 100
c 2
l -141 153 -199 227 80 100
c 2
l -199 227 -260 300 76 100
c 2
l -260 300 -318 366 71 100
c 3
d -141 153 26 85
c 3
d -260 300 23 85
g aL2_3
c 1
l -730 790 -800 740 34 100
c 1
l -800 740 -835 677 45 100
c 1
l -835 677 -840 620 41 100
c 1
l -840 620 -760 580 20 100
c 2
l -730 790 -800 740 26 100
c 2
l -800 740 -835 677 21 100
c 2
l -835 677 -840 620 17 100
c 2
l -840 620 -760 580 12 100
c 3
d -730 790 10 85
c 3
d -835 677 10 85
g aL2_2
c 1
l -440 780 -506 807 52 100
c 1
l -506 807 -575 820 63 100
c 1
l -575 820 -640 820 59 100
c 1
l -640 820 -730 790 38 100
c 2
l -440 780 -506 807 44 100
c 2
l -506 807 -575 820 39 100
c 2
l -575 820 -640 820 35 100
c 2
l -640 820 -730 790 30 100
c 3
d -440 780 14 85
c 3
d -575 820 11 85
g aL2_1
c 1
l -201 464 -231 547 75 100
c 1
l -231 547 -270 620 86 100
c 1
l -270 620 -320 684 82 100
c 1
l -320 684 -379 739 77 100
c 1
l -379 739 -440 780 57 100
c 2
l -201 464 -231 547 67 100
c 2
l -231 547 -270 620 62 100
c 2
l -270 620 -320 684 58 100
c 2
l -320 684 -379 739 53 100
c 2
l -379 739 -440 780 49 100
c 3
d -231 547 20 85
c 3
d -320 684 17 85
g aL2_0
c 1
l -70 120 -96 188 93 100
c 1
l -96 188 -133 285 104 100
c 1
l -133 285 -170 380 100 100
c 1
l -170 380 -201 464 79 100
c 2
l -70 120 -96 188 85 100
c 2
l -96 188 -133 285 80 100
c 2
l -133 285 -170 380 76 100
c 2
l -170 380 -201 464 71 100
c 3
d -96 188 26 85
c 3
d -170 380 23 85
g aL3_3
c 1
l -479 931 -540 900 35 100
c 1
l -540 900 -564 849 46 100
c 1
l -564 849 -560 800 41 100
c 1
l -560 800 -480 780 20 100
c 2
l -479 931 -540 900 27 100
c 2
l -540 900 -564 849 22 100
c 2
l -564 849 -560 800 17 100
c 2
l -560 800 -480 780 12 100
c 3
d -540 900 10 85
c 3
d -560 800 10 85
g aL3_2
c 1
l -194 804 -240 860 54 100
c 1
l -240 860 -319 915 65 100
c 1
l -319 915 -400 940 60 100
c 1
l -400 940 -479 931 39 100
c 2
l -194 804 -240 860 46 100
c 2
l -240 860 -319 915 41 100
c 2
l -319 915 -400 940 36 100
c 2
l -400 940 -479 931 31 100
c 3
d -240 860 13 85
c 3
d -400 940 10 85
g aL3_1
c 1
l -83 505 -97 585 74 100
c 1
l -97 585 -120 660 85 100
c 1
l -120 660 -153 734 80 100
c 1
l -153 734 -194 804 59 100
c 2
l -83 505 -97 585 66 100
c 2
l -97 585 -120 660 61 100
c 2
l -120 660 -153 734 56 100
c 2
l -153 734 -194 804 51 100
c 3
d -97 585 19 85
c 3
d -153 734 16 85
g aL3_0
c 1
l -40 130 -47 207 93 100
c 1
l -47 207 -57 316 104 100
c 1
l -57 316 -70 420 99 100
c 1
l -70 420 -83 505 78 100
c 2
l -40 130 -47 207 85 100
c 2
l -47 207 -57 316 80 100
c 2
l -57 316 -70 420 75 100
c 2
l -70 420 -83 505 70 100
c 3
d -47 207 26 85
c 3
d -70 420 23 85
g head
c 2
f 100 0 -960 70 -930 110 -886 150 -820 176 -761 200 -693 220 -620 232 -562 241 -501 248 -440 250 -380 246 -301 236 -225 220 -160 187 -89 140 -40 74 -10 0 0 -74 -10 -140 -40 -187 -89 -220 -160 -236 -225 -246 -301 -250 -380 -248 -440 -241 -501 -232 -562 -220 -620 -200 -693 -176 -761 -150 -820 -110 -886 -70 -930
c 1
p 1 20 100 0 -960 70 -930 110 -886 150 -820 176 -761 200 -693 220 -620 232 -562 241 -501 248 -440 250 -380 246 -301 236 -225 220 -160 187 -89 140 -40 74 -10 0 0 -74 -10 -140 -40 -187 -89 -220 -160 -236 -225 -246 -301 -250 -380 -248 -440 -241 -501 -232 -562 -220 -620 -200 -693 -176 -761 -150 -820 -110 -886 -70 -930
c 1
p 0 8 40 0 -940 4 -898 10 -839 16 -770 20 -700 22 -644 22 -584 22 -523 22 -461 20 -400 17 -335 12 -266 8 -198 3 -141 0 -100
c 2
b 145 -40 95 75 100 0
c 3
b 145 -40 82 62 100 0
c 2
b -145 -40 95 75 100 0
c 3
b -145 -40 82 62 100 0
g finR
c 2
f 100 100 -800 300 -920 420 -840 340 -660 200 -560
c 1
p 1 14 95 100 -800 300 -920 420 -840 340 -660 200 -560
c 3
l 140 -720 360 -820 8 50
l 180 -640 340 -720 8 50
g finL
c 2
f 100 -100 -800 -300 -920 -420 -840 -340 -660 -200 -560
c 1
p 1 14 95 -100 -800 -300 -920 -420 -840 -340 -660 -200 -560
c 3
l -140 -720 -360 -820 8 50
l -180 -640 -340 -720 8 50
g irisR
c 4
b 145 -40 50 55 95 0
c 2
b 145 -40 12 50 100 0
g irisL
c 4
b -145 -40 50 55 95 0
c 2
b -145 -40 12 50 100 0
g lids
c 1
e 145 -40 95 75 14 100 0
c 1
l 60 -140 220 -110 14 90
c 1
e -145 -40 95 75 14 100 0
c 1
l -60 -140 -220 -110 14 90
g beak
c 2
f 100 -50 60 50 60 0 170
c 1
p 1 12 100 -50 60 50 60 0 170
c 3
l 0 70 0 140 8 80
g lights
c 4
d -100 -700 22 95
c 3
d 120 -620 14 50
c 3
d -60 -500 14 50
c 4
d 140 -400 22 95
c 3
d -150 -340 14 50
c 3
d 50 -280 14 50
c 4
d -100 -180 22 95
c 3
d 150 -180 14 50
c 3
d 0 -820 14 50
g bubbles
c 3
e -500 -500 30 30 8 70 0
c 3
e 550 -800 24 24 8 70 0
c 3
e -620 -100 20 20 8 70 0
c 3
e 200 960 18 18 8 70 0
]];
Figures.Phoenix = [[
g base
g tailA_2
c 1
l -100 700 -91 782 36 100
c 1
l -91 782 -60 869 28 100
c 1
l -60 869 -24 946 20 100
c 1
l -24 946 0 1000 12 100
c 3
l -100 700 -91 782 16 100
c 3
l -91 782 -60 869 13 100
c 3
l -60 869 -24 946 9 100
c 3
l -24 946 0 1000 5 100
g tailA_1
c 1
l 60 400 29 475 68 100
c 1
l 29 475 -22 550 60 100
c 1
l -22 550 -73 625 52 100
c 1
l -73 625 -100 700 44 100
c 3
l 60 400 29 475 31 100
c 3
l 29 475 -22 550 27 100
c 3
l -22 550 -73 625 23 100
c 3
l -73 625 -100 700 20 100
g tailA_0
c 1
l 0 100 16 154 100 100
c 1
l 16 154 40 231 92 100
c 1
l 40 231 59 318 84 100
c 1
l 59 318 60 400 76 100
c 3
l 0 100 16 154 45 100
c 3
l 16 154 40 231 41 100
c 3
l 40 231 59 318 38 100
c 3
l 59 318 60 400 34 100
g tailB_2
c 1
l 400 580 402 656 32 100
c 1
l 402 656 383 744 25 100
c 1
l 383 744 357 824 19 100
c 1
l 357 824 340 880 12 100
c 3
l 400 580 402 656 14 100
c 3
l 402 656 383 744 11 100
c 3
l 383 744 357 824 8 100
c 3
l 357 824 340 880 5 100
g tailB_1
c 1
l 200 360 253 416 58 100
c 1
l 253 416 314 467 52 100
c 1
l 314 467 367 520 45 100
c 1
l 367 520 400 580 39 100
c 3
l 200 360 253 416 26 100
c 3
l 253 416 314 467 23 100
c 3
l 314 467 367 520 20 100
c 3
l 367 520 400 580 17 100
g tailB_0
c 1
l 40 100 68 148 85 100
c 1
l 68 148 108 216 78 100
c 1
l 108 216 153 292 72 100
c 1
l 153 292 200 360 65 100
c 3
l 40 100 68 148 38 100
c 3
l 68 148 108 216 35 100
c 3
l 108 216 153 292 32 100
c 3
l 153 292 200 360 29 100
g tailC_2
c 1
l -400 580 -402 656 32 100
c 1
l -402 656 -383 744 25 100
c 1
l -383 744 -357 824 19 100
c 1
l -357 824 -340 880 12 100
c 3
l -400 580 -402 656 14 100
c 3
l -402 656 -383 744 11 100
c 3
l -383 744 -357 824 8 100
c 3
l -357 824 -340 880 5 100
g tailC_1
c 1
l -200 360 -253 416 58 100
c 1
l -253 416 -314 467 52 100
c 1
l -314 467 -367 520 45 100
c 1
l -367 520 -400 580 39 100
c 3
l -200 360 -253 416 26 100
c 3
l -253 416 -314 467 23 100
c 3
l -314 467 -367 520 20 100
c 3
l -367 520 -400 580 17 100
g tailC_0
c 1
l -40 100 -68 148 85 100
c 1
l -68 148 -107 216 78 100
c 1
l -107 216 -153 292 72 100
c 1
l -153 292 -200 360 65 100
c 3
l -40 100 -68 148 38 100
c 3
l -68 148 -107 216 35 100
c 3
l -107 216 -153 292 32 100
c 3
l -153 292 -200 360 29 100
g tailD_2
c 1
l 640 400 673 472 26 100
c 1
l 673 472 689 560 21 100
c 1
l 689 560 695 643 15 100
c 1
l 695 643 700 700 10 100
c 3
l 640 400 673 472 12 100
c 3
l 673 472 689 560 9 100
c 3
l 689 560 695 643 7 100
c 3
l 695 643 700 700 5 100
g tailD_1
c 1
l 340 240 418 277 48 100
c 1
l 418 277 503 311 43 100
c 1
l 503 311 581 350 37 100
c 1
l 581 350 640 400 32 100
c 3
l 340 240 418 277 22 100
c 3
l 418 277 503 311 19 100
c 3
l 503 311 581 350 17 100
c 3
l 581 350 640 400 14 100
g tailD_0
c 1
l 80 80 126 109 70 100
c 1
l 126 109 191 150 65 100
c 1
l 191 150 266 196 59 100
c 1
l 266 196 340 240 54 100
c 3
l 80 80 126 109 32 100
c 3
l 126 109 191 150 29 100
c 3
l 191 150 266 196 27 100
c 3
l 266 196 340 240 24 100
g tailE_2
c 1
l -640 400 -673 472 26 100
c 1
l -673 472 -689 560 21 100
c 1
l -689 560 -695 643 15 100
c 1
l -695 643 -700 700 10 100
c 3
l -640 400 -673 472 12 100
c 3
l -673 472 -689 560 9 100
c 3
l -689 560 -695 643 7 100
c 3
l -695 643 -700 700 5 100
g tailE_1
c 1
l -340 240 -418 277 48 100
c 1
l -418 277 -503 311 43 100
c 1
l -503 311 -581 350 37 100
c 1
l -581 350 -640 400 32 100
c 3
l -340 240 -418 277 22 100
c 3
l -418 277 -503 311 19 100
c 3
l -503 311 -581 350 17 100
c 3
l -581 350 -640 400 14 100
g tailE_0
c 1
l -80 80 -126 109 70 100
c 1
l -126 109 -191 150 65 100
c 1
l -191 150 -266 196 59 100
c 1
l -266 196 -340 240 54 100
c 3
l -80 80 -126 109 32 100
c 3
l -126 109 -191 150 29 100
c 3
l -191 150 -266 196 27 100
c 3
l -266 196 -340 240 24 100
g wingRo
c 2
b 139 -568 70 370 100 60
c 1
e 139 -568 70 370 10 90 60
c 3
l 139 -568 162 -789 12 80
c 2
b 247 -604 75 430 100 200
c 1
e 247 -604 75 430 10 90 200
c 3
l 247 -604 335 -847 12 80
c 2
b 363 -590 75 470 100 340
c 1
e 363 -590 75 470 10 90 340
c 3
l 363 -590 521 -823 12 80
c 2
b 464 -528 75 490 100 480
c 1
e 464 -528 75 490 10 90 480
c 3
l 464 -528 683 -725 12 80
c 2
b 524 -425 72 480 100 620
c 1
e 524 -425 72 480 10 90 620
c 3
l 524 -425 778 -561 12 80
c 2
b 537 -309 70 450 100 760
c 1
e 537 -309 70 450 10 90 760
c 3
l 537 -309 799 -374 12 80
c 2
b 510 -200 66 410 100 900
c 1
e 510 -200 66 410 10 90 900
c 3
l 510 -200 756 -200 12 80
c 2
b 449 -113 62 360 100 1040
c 1
e 449 -113 62 360 10 90 1040
c 3
l 449 -113 659 -61 12 80
g wingR
c 1
b 160 -443 60 250 100 140
c 1
e 160 -443 60 250 10 90 140
c 1
b 250 -460 64 300 100 300
c 1
e 250 -460 64 300 10 90 300
c 1
b 337 -429 64 330 100 460
c 1
e 337 -429 64 330 10 90 460
c 1
b 400 -360 64 340 100 620
c 1
e 400 -360 64 340 10 90 620
c 1
b 413 -267 60 320 100 780
c 1
e 413 -267 60 320 10 90 780
c 1
b 389 -180 56 290 100 940
c 1
e 389 -180 56 290 10 90 940
g wingLo
c 2
b -139 -568 70 370 100 3540
c 1
e -139 -568 70 370 10 90 3540
c 3
l -139 -568 -162 -789 12 80
c 2
b -247 -604 75 430 100 3400
c 1
e -247 -604 75 430 10 90 3400
c 3
l -247 -604 -335 -847 12 80
c 2
b -363 -590 75 470 100 3260
c 1
e -363 -590 75 470 10 90 3260
c 3
l -363 -590 -521 -823 12 80
c 2
b -464 -528 75 490 100 3120
c 1
e -464 -528 75 490 10 90 3120
c 3
l -464 -528 -683 -725 12 80
c 2
b -524 -425 72 480 100 2980
c 1
e -524 -425 72 480 10 90 2980
c 3
l -524 -425 -778 -561 12 80
c 2
b -537 -309 70 450 100 2840
c 1
e -537 -309 70 450 10 90 2840
c 3
l -537 -309 -799 -374 12 80
c 2
b -510 -200 66 410 100 2700
c 1
e -510 -200 66 410 10 90 2700
c 3
l -510 -200 -756 -200 12 80
c 2
b -449 -113 62 360 100 2560
c 1
e -449 -113 62 360 10 90 2560
c 3
l -449 -113 -659 -61 12 80
g wingL
c 1
b -160 -443 60 250 100 3460
c 1
e -160 -443 60 250 10 90 3460
c 1
b -250 -460 64 300 100 3300
c 1
e -250 -460 64 300 10 90 3300
c 1
b -337 -429 64 330 100 3140
c 1
e -337 -429 64 330 10 90 3140
c 1
b -400 -360 64 340 100 2980
c 1
e -400 -360 64 340 10 90 2980
c 1
b -413 -267 60 320 100 2820
c 1
e -413 -267 60 320 10 90 2820
c 1
b -389 -180 56 290 100 2660
c 1
e -389 -180 56 290 10 90 2660
g body
c 2
b 0 -120 130 280 100 0
c 1
e 0 -120 130 280 14 100 0
c 3
b 0 -40 70 170 90 0
c 1
l -60 120 -100 260 20 100
l -100 260 -150 300 14 100
l -100 260 -80 320 14 100
c 1
l 60 120 100 260 20 100
l 100 260 150 300 14 100
l 100 260 80 320 14 100
g heart
c 4
d 0 0 35 100
g neck
c 2
l 0 -280 20 -500 110 100
c 1
p 0 12 90 -55 -300 -30 -500
p 0 12 90 75 -300 70 -500
g head
c 2
b 20 -580 85 75 100 0
c 1
e 20 -580 85 75 14 100 0
c 3
f 100 -40 -600 -160 -560 -40 -520
c 1
p 1 10 100 -40 -600 -160 -560 -40 -520
c 4
d 0 -600 16 100
g crestA_1
c 1
l -36 -844 -80 -900 25 100
c 1
l -80 -900 -125 -947 16 100
c 1
l -125 -947 -160 -980 8 100
c 3
l -36 -844 -80 -900 11 100
c 3
l -80 -900 -125 -947 7 100
c 3
l -125 -947 -160 -980 4 100
g crestA_0
c 1
l 20 -640 15 -702 50 100
c 1
l 15 -702 0 -780 42 100
c 1
l 0 -780 -36 -844 33 100
c 3
l 20 -640 15 -702 23 100
c 3
l 15 -702 0 -780 19 100
c 3
l 0 -780 -36 -844 15 100
g crestB_1
c 1
l 148 -857 200 -900 23 100
c 1
l 200 -900 256 -926 15 100
c 1
l 256 -926 300 -940 8 100
c 3
l 148 -857 200 -900 10 100
c 3
l 200 -900 256 -926 7 100
c 3
l 256 -926 300 -940 4 100
g crestB_0
c 1
l 40 -640 64 -714 45 100
c 1
l 64 -714 100 -800 38 100
c 1
l 100 -800 148 -857 30 100
c 3
l 40 -640 64 -714 20 100
c 3
l 64 -714 100 -800 17 100
c 3
l 100 -800 148 -857 14 100
g crestC_1
c 1
l 40 -820 40 -886 25 100
c 1
l 40 -886 40 -940 16 100
c 1
l 40 -940 60 -1020 8 100
c 3
l 40 -820 40 -886 11 100
c 3
l 40 -886 40 -940 7 100
c 3
l 40 -940 60 -1020 4 100
g crestC_0
c 1
l 20 -640 26 -689 50 100
c 1
l 26 -689 34 -758 42 100
c 1
l 34 -758 40 -820 33 100
c 3
l 20 -640 26 -689 23 100
c 3
l 26 -689 34 -758 19 100
c 3
l 34 -758 40 -820 15 100
g sparks
c 3
d -700 -500 20 95
c 3
d 760 -620 20 95
c 3
d -840 -50 20 95
c 3
d 900 -200 20 95
c 3
d -400 500 20 95
c 3
d 450 620 20 95
]];
Figures.Kitsune = [[
g base
g tail0
c 2
b -396 344 120 400 100 -820
c 1
e -396 344 120 400 12 90 -820
c 3
b -697 302 100 112 100 -820
g tail1
c 2
b -369 216 120 413 100 -635
c 1
e -369 216 120 413 12 90 -635
c 3
b -650 76 100 116 100 -635
g tail2
c 2
b -301 99 120 425 100 -450
c 1
e -301 99 120 425 12 90 -450
c 3
b -529 -129 100 119 100 -450
g tail3
c 2
b -195 8 120 438 100 -265
c 1
e -195 8 120 438 12 90 -265
c 3
b -344 -289 100 123 100 -265
g tail4
c 2
b -63 -46 120 450 100 -80
c 1
e -63 -46 120 450 12 90 -80
c 3
b -110 -384 100 126 100 -80
g tail5
c 2
b 80 -30 120 438 100 105
c 1
e 80 -30 120 438 12 90 105
c 3
b 140 -357 100 123 100 105
g tail6
c 2
b 206 28 120 425 100 290
c 1
e 206 28 120 425 12 90 290
c 3
b 363 -254 100 119 100 290
g tail7
c 2
b 304 121 120 413 100 475
c 1
e 304 121 120 413 12 90 475
c 3
b 535 -90 100 116 100 475
g tail8
c 2
b 365 237 120 400 100 660
c 1
e 365 237 120 400 12 90 660
c 3
b 643 114 100 112 100 660
g torso
c 2
b 260 600 170 220 100 120
c 1
e 260 600 170 220 14 100 120
c 2
l 100 340 100 860 100 100
c 1
p 0 12 90 50 400 50 860
p 0 12 90 150 400 150 860
c 3
b 100 900 75 45 100 0
c 1
e 100 900 75 45 12 90 0
c 2
b -260 600 170 220 100 -120
c 1
e -260 600 170 220 14 100 -120
c 2
l -100 340 -100 860 100 100
c 1
p 0 12 90 -50 400 -50 860
p 0 12 90 -150 400 -150 860
c 3
b -100 900 75 45 100 0
c 1
e -100 900 75 45 12 90 0
c 2
b 0 360 200 300 100 0
c 1
e 0 360 200 300 14 100 0
c 3
b 0 320 120 220 100 0
c 1
p 0 10 60 -100 200 -56 234 0 260 56 234 100 200
g earR
c 2
f 100 100 -220 200 -600 300 -640 300 -180
c 1
p 1 14 100 100 -220 200 -600 300 -640 300 -180
c 3
f 100 150 -240 220 -500 270 -520 270 -220
g earL
c 2
f 100 -100 -220 -200 -600 -300 -640 -300 -180
c 1
p 1 14 100 -100 -220 -200 -600 -300 -640 -300 -180
c 3
f 100 -150 -240 -220 -500 -270 -520 -270 -220
g head
c 2
f 100 0 -300 120 -280 260 -200 300 -80 200 60 100 140 40 200 0 220 -40 200 -100 140 -200 60 -300 -80 -260 -200 -120 -280
c 1
p 1 16 100 0 -300 120 -280 260 -200 300 -80 200 60 100 140 40 200 0 220 -40 200 -100 140 -200 60 -300 -80 -260 -200 -120 -280
c 3
f 100 0 0 80 0 180 60 100 140 40 200 0 220 -40 200 -100 140 -180 60 -80 0
c 4
l 70 -120 150 -60 20 100
l 140 -60 240 -100 12 100
l 140 0 260 -10 12 90
d 110 -100 18 100
l -70 -120 -150 -60 20 100
l -140 -60 -240 -100 12 100
l -140 0 -260 -10 12 90
d -110 -100 18 100
c 1
d 0 180 26 100
l 0 200 0 260 8 80
p 0 8 80 -70 280 -39 269 0 260 39 269 70 280
c 4
p 1 10 100 -30 -280 0 -220 30 -280
g branchL
c 1
p 0 12 80 -950 -460 -913 -495 -859 -545 -800 -600 -754 -643 -703 -690 -651 -737 -600 -780 -545 -821 -487 -861 -436 -896 -400 -920
c 4
b -700 -690 39 39 90 0
c 4
b -633 -642 39 39 90 0
c 4
b -659 -563 39 39 90 0
c 4
b -741 -563 39 39 90 0
c 4
b -767 -642 39 39 90 0
c 3
d -700 -620 28 100
c 4
b -550 -875 30 30 90 0
c 4
b -498 -837 30 30 90 0
c 4
b -518 -776 30 30 90 0
c 4
b -582 -776 30 30 90 0
c 4
b -602 -837 30 30 90 0
c 3
d -550 -820 22 100
g branchR
c 1
p 0 12 80 950 -400 916 -440 867 -498 820 -560 791 -609 764 -661 735 -713 700 -760 651 -802 592 -842 538 -876 500 -900
c 4
b 660 -850 39 39 90 0
c 4
b 727 -802 39 39 90 0
c 4
b 701 -723 39 39 90 0
c 4
b 619 -723 39 39 90 0
c 4
b 593 -802 39 39 90 0
c 3
d 660 -780 28 100
c 4
b 800 -610 28 28 90 0
c 4
b 848 -575 28 28 90 0
c 4
b 829 -520 28 28 90 0
c 4
b 771 -520 28 28 90 0
c 4
b 752 -575 28 28 90 0
c 3
d 800 -560 20 100
g petals
c 4
b -300 -700 25 45 90 -180
c 4
b 300 -740 25 45 90 180
c 4
b -860 100 25 45 90 -516
c 4
b 880 100 25 45 90 528
c 4
b 500 700 25 45 90 300
c 4
b -520 760 25 45 90 -312
]];
Figures.Reaper = [[
g base
g scythe
c 3
l 580 960 460 -920 24 100
c 1
l 440 -900 409 -916 70 100
c 1
l 409 -916 365 -941 65 100
c 1
l 365 -941 313 -968 59 100
c 1
l 313 -968 257 -990 54 100
c 1
l 257 -990 200 -1000 48 100
c 1
l 200 -1000 151 -999 43 100
c 1
l 151 -999 99 -993 37 100
c 1
l 99 -993 44 -982 32 100
c 1
l 44 -982 -12 -967 26 100
c 1
l -12 -967 -67 -946 21 100
c 1
l -67 -946 -120 -920 15 100
c 1
l -120 -920 -166 -891 10 100
c 1
l -166 -891 -214 -856 4 100
c 1
l -214 -856 -262 -816 4 100
c 1
l -262 -816 -308 -774 4 100
c 1
l -308 -774 -351 -732 4 100
c 1
l -351 -732 -389 -693 4 100
c 1
l -389 -693 -420 -660 4 100
c 1
l -420 -660 -466 -593 4 100
c 1
l -466 -593 -487 -538 4 100
c 1
l -487 -538 -500 -500 4 100
c 2
l 440 -890 409 -906 40 100
c 2
l 409 -906 365 -931 37 100
c 2
l 365 -931 313 -958 34 100
c 2
l 313 -958 257 -980 31 100
c 2
l 257 -980 200 -990 28 100
c 2
l 200 -990 151 -989 25 100
c 2
l 151 -989 99 -983 22 100
c 2
l 99 -983 44 -972 19 100
c 2
l 44 -972 -12 -957 16 100
c 2
l -12 -957 -67 -936 13 100
c 2
l -67 -936 -120 -910 10 100
c 2
l -120 -910 -166 -881 7 100
c 2
l -166 -881 -214 -846 4 100
c 2
l -214 -846 -262 -806 4 100
c 2
l -262 -806 -308 -764 4 100
c 2
l -308 -764 -351 -722 4 100
c 2
l -351 -722 -389 -683 4 100
c 2
l -389 -683 -420 -650 4 100
c 2
l -420 -650 -466 -583 4 100
c 2
l -466 -583 -487 -528 4 100
c 2
l -487 -528 -500 -490 4 100
c 4
p 0 12 100 420 -960 383 -978 330 -1004 267 -1028 200 -1040 142 -1040 78 -1035 11 -1024 -56 -1006 -120 -980 -173 -950 -229 -912 -284 -869 -336 -824 -382 -780 -420 -740 -461 -682 -489 -625 -507 -575 -520 -540
c 3
d 460 -920 26 100
g hem
c 2
f 100 393 80 400 140 460 500 580 880 480 800 420 960 320 820 260 970 160 840 80 960 0 860 -80 960 -160 840 -260 970 -320 820 -420 960 -480 800 -580 880 -460 500 -400 140 -393 80
c 1
l 398 120 400 140 16 100
l 400 140 460 500 16 100
l 460 500 580 880 16 100
l 580 880 480 800 16 100
l 480 800 420 960 16 100
l 420 960 320 820 16 100
l 320 820 260 970 16 100
l 260 970 160 840 16 100
l 160 840 80 960 16 100
l 80 960 0 860 16 100
l 0 860 -80 960 16 100
l -80 960 -160 840 16 100
l -160 840 -260 970 16 100
l -260 970 -320 820 16 100
l -320 820 -420 960 16 100
l -420 960 -480 800 16 100
l -480 800 -580 880 16 100
l -580 880 -460 500 16 100
l -460 500 -400 140 16 100
l -400 140 -398 120 16 100
c 1
p 0 8 40 162 406 200 900
p 0 8 40 287 419 340 860
p 0 8 40 -162 406 -200 900
g cloak
c 2
f 100 0 -900 90 -880 170 -800 200 -660 190 -540 300 -420 360 -200 398 120 -398 120 -360 -200 -300 -420 -190 -540 -200 -660 -170 -800 -90 -880
c 1
l 0 -900 90 -880 16 100
l 90 -880 170 -800 16 100
l 170 -800 200 -660 16 100
l 200 -660 190 -540 16 100
l 190 -540 300 -420 16 100
l 300 -420 360 -200 16 100
l 360 -200 398 120 16 100
l -398 120 -360 -200 16 100
l -360 -200 -300 -420 16 100
l -300 -420 -190 -540 16 100
l -190 -540 -200 -660 16 100
l -200 -660 -170 -800 16 100
l -170 -800 -90 -880 16 100
l -90 -880 0 -900 16 100
p 0 8 40 100 -400 165 406
p 0 8 40 200 -300 291 419
p 0 8 40 -100 -400 -165 406
g torso
g hood
c 1
f 100 -100 -760 0 -820 100 -760 110 -620 60 -540 -60 -540 -110 -620
c 2
f 100 -85 -740 0 -790 85 -740 95 -620 50 -560 -50 -560 -95 -620
c 3
p 0 6 60 -40 -600 -20 -570 0 -600 20 -570 40 -600
g eyes
c 4
f 100 -70 -680 -20 -660 -30 -630 -75 -650
f 100 70 -680 20 -660 30 -630 75 -650
g handR
c 3
l 480 -200 540 -220 13 100
c 3
l 492 -170 540 -175 13 100
c 3
l 504 -140 540 -130 13 100
c 3
l 516 -110 540 -85 13 100
g armR
c 2
l 260 -440 460 -200 100 100
c 1
p 0 10 70 220 -500 400 -300 500 -200
g armL
c 2
l -260 -440 -400 -100 100 100
g fire0
c 4
b -700 300 39 70 95 0
b -710 223 21 42 90 120
c 3
b -700 314 18 35 100 0
g fire1
c 4
b -550 650 28 50 95 0
b -557 595 15 30 90 120
c 3
b -550 660 13 25 100 0
g fire2
c 4
b 780 500 33 60 95 0
b 771 434 18 36 90 120
c 3
b 780 512 15 30 100 0
g fire3
c 4
b -820 -200 25 45 95 0
b -827 -249 14 27 90 120
c 3
b -820 -191 11 23 100 0
g fire4
c 4
b 700 -500 28 50 95 0
b 693 -555 15 30 90 120
c 3
b 700 -490 13 25 100 0
]];
Figures.Mecha = [[
g base
g thrR
c 2
f 100 220 -500 340 -900 440 -900 400 -450
c 1
p 1 12 100 220 -500 340 -900 440 -900 400 -450
g thrRf
c 4
l 390 -860 370 -620 12 100
g thrL
c 2
f 100 -220 -500 -340 -900 -440 -900 -400 -450
c 1
p 1 12 100 -220 -500 -340 -900 -440 -900 -400 -450
g thrLf
c 4
l -390 -860 -370 -620 12 100
g armRf
c 2
f 100 600 620 820 620 800 940 620 940
c 1
p 1 14 100 600 620 820 620 800 940 620 940
c 4
f 100 660 900 760 900 760 960 660 960
g armR
c 2
f 100 620 -100 820 -100 880 300 800 620 580 620 540 300
c 1
p 1 14 100 620 -100 820 -100 880 300 800 620 580 620 540 300
c 1
p 0 10 80 620 0 820 0
p 0 10 80 600 200 840 200
g armLf
c 2
f 100 -600 620 -820 620 -800 940 -620 940
c 1
p 1 14 100 -600 620 -820 620 -800 940 -620 940
c 4
f 100 -660 900 -760 900 -760 960 -660 960
g armL
c 2
f 100 -620 -100 -820 -100 -880 300 -800 620 -580 620 -540 300
c 1
p 1 14 100 -620 -100 -820 -100 -880 300 -800 620 -580 620 -540 300
c 1
p 0 10 80 -620 0 -820 0
p 0 10 80 -600 200 -840 200
g torso
c 2
f 100 0 -400 200 -400 420 -300 500 -100 460 300 340 600 200 700 0 700 -200 700 -340 600 -460 300 -500 -100 -420 -300 -200 -400
c 1
p 1 16 100 0 -400 200 -400 420 -300 500 -100 460 300 340 600 200 700 0 700 -200 700 -340 600 -460 300 -500 -100 -420 -300 -200 -400
c 1
p 0 10 70 -340 300 -200 500 200 500 340 300
c 3
l -200 360 -200 620 8 60
l 200 360 200 620 8 60
c 2
e 0 50 200 200 0 0 0
c 1
e 0 50 200 200 16 100 0
e 0 50 150 150 8 60 0
g spokes
c 4
l 190 50 100 50 10 90
c 4
l 95 215 50 137 10 90
c 4
l -95 215 -50 137 10 90
c 4
l -190 50 -100 50 10 90
c 4
l -95 -115 -50 -37 10 90
c 4
l 95 -115 50 -37 10 90
g core
c 4
d 0 50 80 100
g circuits
c 4
p 0 8 90 -200 50 -340 50 -340 -150
d -340 -150 14 100
p 0 8 90 200 50 340 50 340 220
d 340 220 14 100
g pauldR
c 2
f 100 360 -420 660 -460 900 -340 940 -120 620 -100 400 -200
c 1
p 1 16 100 360 -420 660 -460 900 -340 940 -120 620 -100 400 -200
c 2
f 100 460 -200 700 -140 920 -140 900 0 620 0 460 -60
c 1
p 1 12 100 460 -200 700 -140 920 -140 900 0 620 0 460 -60
c 4
l 500 -360 840 -300 12 100
c 3
p 0 8 70 420 -400 600 -420 800 -360
g pauldL
c 2
f 100 -360 -420 -660 -460 -900 -340 -940 -120 -620 -100 -400 -200
c 1
p 1 16 100 -360 -420 -660 -460 -900 -340 -940 -120 -620 -100 -400 -200
c 2
f 100 -460 -200 -700 -140 -920 -140 -900 0 -620 0 -460 -60
c 1
p 1 12 100 -460 -200 -700 -140 -920 -140 -900 0 -620 0 -460 -60
c 4
l -500 -360 -840 -300 12 100
c 3
p 0 8 70 -420 -400 -600 -420 -800 -360
g neck
c 1
p 0 12 90 -80 -400 -100 -460 -81 -494 -60 -520
p 0 12 90 80 -400 100 -460 81 -494 60 -520
g antR
c 2
l 180 -800 340 -990 20 100
c 1
l 180 -800 340 -990 10 100
c 4
d 340 -990 20 100
g antL
c 2
l -180 -800 -340 -990 20 100
c 1
l -180 -800 -340 -990 10 100
c 4
d -340 -990 20 100
g head
c 2
f 100 0 -820 140 -820 240 -740 270 -600 240 -480 140 -400 0 -380 -140 -400 -240 -480 -270 -600 -240 -740 -140 -820
c 1
p 1 18 100 0 -820 140 -820 240 -740 270 -600 240 -480 140 -400 0 -380 -140 -400 -240 -480 -270 -600 -240 -740 -140 -820
c 1
p 0 14 90 -120 -820 -60 -940 60 -940 120 -820
c 1
l -100 -500 100 -500 10 70
l -80 -460 80 -460 10 70
c 3
l 0 -820 0 -700 10 70
g visor
c 4
f 100 -210 -680 210 -680 170 -580 -170 -580
c 2
l -200 -630 200 -630 10 70
g sparks
c 4
d -700 -700 16 90
c 4
d 740 -740 16 90
c 4
d -900 300 16 90
c 4
d 900 400 16 90
]];
Figures.Eye = [[
c 1
p 0 60 100 -950 80 -923 50 -890 9 -850 -39 -805 -93 -756 -151 -705 -209 -653 -265 -600 -317 -549 -363 -500 -400 -440 -437 -379 -468 -316 -494 -253 -514 -190 -530 -126 -541 -63 -548 0 -550 63 -548 126 -541 190 -530 253 -514 316 -494 379 -468 440 -437 500 -400 549 -363 600 -317 653 -265 705 -209 756 -151 805 -93 850 -39 890 9 923 50 950 80
c 1
p 0 50 90 -950 80 -916 103 -870 135 -816 172 -756 214 -692 256 -627 296 -562 332 -500 360 -440 382 -379 402 -316 419 -253 434 -190 445 -126 453 -63 458 0 460 63 458 126 453 190 445 253 434 316 419 379 402 440 382 500 360 562 332 627 296 692 256 756 214 816 172 870 135 916 103 950 80
c 2
b 0 0 550 380 70 0
c 3
b 0 -20 300 300 100 0
c 4
d 0 -20 200 100
c 2
b 0 -20 50 220 100 0
c 1
l -800 -100 -864 -240 30 90
c 1
l -600 -200 -648 -340 30 90
c 1
l -400 -300 -432 -440 30 90
c 1
l -200 -400 -216 -540 30 90
c 1
l 0 -500 0 -640 30 90
c 1
l 200 -400 216 -540 30 90
c 1
l 400 -300 432 -440 30 90
c 1
l 600 -200 648 -340 30 90
c 1
l 800 -100 864 -240 30 90
]];
Figures.Fairy = [[
c 3
b -460 -440 360 170 55 -360
c 1
e -460 -440 360 170 14 95 -360
c 1
l -227 -609 -693 -271 6 50
c 3
b 460 -440 360 170 55 360
c 1
e 460 -440 360 170 14 95 360
c 1
l 227 -609 693 -271 6 50
c 3
b -340 -120 260 120 55 -180
c 1
e -340 -120 260 120 14 95 -180
c 1
l -142 -184 -538 -56 6 50
c 3
b 340 -120 260 120 55 180
c 1
e 340 -120 260 120 14 95 180
c 1
l 142 -184 538 -56 6 50
c 4
b 0 -620 220 230 95 0
c 4
l -190 -580 -270 -200 70 95
c 4
l 190 -580 270 -200 70 95
c 3
l -70 300 -100 720 55 100
l 70 300 120 680 55 100
c 4
b -100 770 70 40 100 100
b 120 730 70 40 100 -100
c 2
f 100 -60 -440 60 -440 100 -300 320 280 180 360 0 300 -180 360 -320 280 -100 -300
c 1
p 1 14 100 -60 -440 60 -440 100 -300 320 280 180 360 0 300 -180 360 -320 280 -100 -300
c 4
l -90 -240 90 -240 30 100
c 3
l -80 -380 -400 -220 60 100
l 80 -380 340 -620 60 100
c 1
l 340 -620 620 -950 22 100
c 4
f 100 640 -1130 677 -1031 783 -1026 700 -961 728 -859 640 -917 552 -859 580 -961 497 -1026 603 -1031
d 640 -980 50 100
c 3
b 0 -580 130 140 100 0
c 1
e 0 -580 130 140 12 90 0
c 1
l -60 -570 -20 -560 10 100
l 20 -560 60 -570 10 100
c 4
f 100 0 -930 22 -871 86 -868 36 -828 53 -767 0 -802 -53 -767 -36 -828 -86 -868 -22 -871
c 4
d -500 400 25 95
c 4
d 500 300 25 95
c 4
d -200 900 25 95
c 4
d 840 -600 25 95
c 4
d 780 -1020 25 95
]];
Figures.KrakenArm = [[
c 1
l 20 1100 38 1048 200 100
c 1
l 38 1048 65 975 195 100
c 1
l 65 975 94 889 189 100
c 1
l 94 889 120 800 184 100
c 1
l 120 800 138 726 178 100
c 1
l 138 726 155 647 173 100
c 1
l 155 647 172 565 168 100
c 1
l 172 565 187 482 162 100
c 1
l 187 482 200 400 157 100
c 1
l 200 400 212 320 152 100
c 1
l 212 320 222 240 146 100
c 1
l 222 240 230 160 141 100
c 1
l 230 160 236 80 135 100
c 1
l 236 80 240 0 130 100
c 1
l 240 0 241 -81 125 100
c 1
l 241 -81 239 -163 119 100
c 1
l 239 -163 235 -244 114 100
c 1
l 235 -244 229 -324 109 100
c 1
l 229 -324 220 -400 103 100
c 1
l 220 -400 205 -493 98 100
c 1
l 205 -493 186 -584 92 100
c 1
l 186 -584 164 -668 87 100
c 1
l 164 -668 140 -740 82 100
c 1
l 140 -740 101 -823 76 100
c 1
l 101 -823 59 -888 71 100
c 1
l 59 -888 20 -920 66 100
c 1
l 20 -920 -31 -880 60 100
c 1
l -31 -880 -60 -800 55 100
c 1
l -60 -800 -35 -723 49 100
c 1
l -35 -723 0 -660 44 100
c 2
l 20 1100 38 1048 170 100
c 2
l 38 1048 65 975 165 100
c 2
l 65 975 94 889 159 100
c 2
l 94 889 120 800 154 100
c 2
l 120 800 138 726 148 100
c 2
l 138 726 155 647 143 100
c 2
l 155 647 172 565 138 100
c 2
l 172 565 187 482 132 100
c 2
l 187 482 200 400 127 100
c 2
l 200 400 212 320 122 100
c 2
l 212 320 222 240 116 100
c 2
l 222 240 230 160 111 100
c 2
l 230 160 236 80 105 100
c 2
l 236 80 240 0 100 100
c 2
l 240 0 241 -81 95 100
c 2
l 241 -81 239 -163 89 100
c 2
l 239 -163 235 -244 84 100
c 2
l 235 -244 229 -324 79 100
c 2
l 229 -324 220 -400 73 100
c 2
l 220 -400 205 -493 68 100
c 2
l 205 -493 186 -584 62 100
c 2
l 186 -584 164 -668 57 100
c 2
l 164 -668 140 -740 52 100
c 2
l 140 -740 101 -823 46 100
c 2
l 101 -823 59 -888 41 100
c 2
l 59 -888 20 -920 36 100
c 2
l 20 -920 -31 -880 30 100
c 2
l -31 -880 -60 -800 25 100
c 2
l -60 -800 -35 -723 19 100
c 2
l -35 -723 0 -660 14 100
c 3
d 5 1048 49 85
c 3
d 63 889 46 85
c 3
d 109 726 43 85
c 3
d 146 565 40 85
c 3
d 176 400 36 85
c 3
d 200 240 33 85
c 3
d 216 80 30 85
c 3
d 223 -81 27 85
c 3
d 219 -244 24 85
c 3
d 206 -400 20 85
c 3
d 175 -584 17 85
c 3
d 131 -740 14 85
c 3
d 52 -888 12 85
c 3
d -36 -880 12 85
c 3
d -38 -723 12 85
]];
Figures.KrakenArmL = [[
c 1
l -20 1100 -38 1048 200 100
c 1
l -38 1048 -65 975 195 100
c 1
l -65 975 -94 889 189 100
c 1
l -94 889 -120 800 184 100
c 1
l -120 800 -138 726 178 100
c 1
l -138 726 -155 647 173 100
c 1
l -155 647 -172 565 168 100
c 1
l -172 565 -187 482 162 100
c 1
l -187 482 -200 400 157 100
c 1
l -200 400 -212 320 152 100
c 1
l -212 320 -222 240 146 100
c 1
l -222 240 -230 160 141 100
c 1
l -230 160 -236 80 135 100
c 1
l -236 80 -240 0 130 100
c 1
l -240 0 -241 -81 125 100
c 1
l -241 -81 -239 -163 119 100
c 1
l -239 -163 -235 -244 114 100
c 1
l -235 -244 -229 -324 109 100
c 1
l -229 -324 -220 -400 103 100
c 1
l -220 -400 -205 -493 98 100
c 1
l -205 -493 -186 -584 92 100
c 1
l -186 -584 -164 -668 87 100
c 1
l -164 -668 -140 -740 82 100
c 1
l -140 -740 -101 -823 76 100
c 1
l -101 -823 -59 -888 71 100
c 1
l -59 -888 -20 -920 66 100
c 1
l -20 -920 31 -880 60 100
c 1
l 31 -880 60 -800 55 100
c 1
l 60 -800 35 -723 49 100
c 1
l 35 -723 0 -660 44 100
c 2
l -20 1100 -38 1048 170 100
c 2
l -38 1048 -65 975 165 100
c 2
l -65 975 -94 889 159 100
c 2
l -94 889 -120 800 154 100
c 2
l -120 800 -138 726 148 100
c 2
l -138 726 -155 647 143 100
c 2
l -155 647 -172 565 138 100
c 2
l -172 565 -187 482 132 100
c 2
l -187 482 -200 400 127 100
c 2
l -200 400 -212 320 122 100
c 2
l -212 320 -222 240 116 100
c 2
l -222 240 -230 160 111 100
c 2
l -230 160 -236 80 105 100
c 2
l -236 80 -240 0 100 100
c 2
l -240 0 -241 -81 95 100
c 2
l -241 -81 -239 -163 89 100
c 2
l -239 -163 -235 -244 84 100
c 2
l -235 -244 -229 -324 79 100
c 2
l -229 -324 -220 -400 73 100
c 2
l -220 -400 -205 -493 68 100
c 2
l -205 -493 -186 -584 62 100
c 2
l -186 -584 -164 -668 57 100
c 2
l -164 -668 -140 -740 52 100
c 2
l -140 -740 -101 -823 46 100
c 2
l -101 -823 -59 -888 41 100
c 2
l -59 -888 -20 -920 36 100
c 2
l -20 -920 31 -880 30 100
c 2
l 31 -880 60 -800 25 100
c 2
l 60 -800 35 -723 19 100
c 2
l 35 -723 0 -660 14 100
c 3
d -5 1048 49 85
c 3
d -63 889 46 85
c 3
d -109 726 43 85
c 3
d -146 565 40 85
c 3
d -176 400 36 85
c 3
d -200 240 33 85
c 3
d -216 80 30 85
c 3
d -223 -81 27 85
c 3
d -219 -244 24 85
c 3
d -206 -400 20 85
c 3
d -175 -584 17 85
c 3
d -131 -740 14 85
c 3
d -52 -888 12 85
c 3
d 36 -880 12 85
c 3
d 38 -723 12 85
]];
Figures.KrakenArmT = [[
c 1
l 20 -1100 38 -1048 200 100
c 1
l 38 -1048 65 -975 195 100
c 1
l 65 -975 94 -889 189 100
c 1
l 94 -889 120 -800 184 100
c 1
l 120 -800 138 -726 178 100
c 1
l 138 -726 155 -647 173 100
c 1
l 155 -647 172 -565 168 100
c 1
l 172 -565 187 -482 162 100
c 1
l 187 -482 200 -400 157 100
c 1
l 200 -400 212 -320 152 100
c 1
l 212 -320 222 -240 146 100
c 1
l 222 -240 230 -160 141 100
c 1
l 230 -160 236 -80 135 100
c 1
l 236 -80 240 0 130 100
c 1
l 240 0 241 81 125 100
c 1
l 241 81 239 163 119 100
c 1
l 239 163 235 244 114 100
c 1
l 235 244 229 324 109 100
c 1
l 229 324 220 400 103 100
c 1
l 220 400 205 493 98 100
c 1
l 205 493 186 584 92 100
c 1
l 186 584 164 668 87 100
c 1
l 164 668 140 740 82 100
c 1
l 140 740 101 823 76 100
c 1
l 101 823 59 888 71 100
c 1
l 59 888 20 920 66 100
c 1
l 20 920 -31 880 60 100
c 1
l -31 880 -60 800 55 100
c 1
l -60 800 -35 723 49 100
c 1
l -35 723 0 660 44 100
c 2
l 20 -1100 38 -1048 170 100
c 2
l 38 -1048 65 -975 165 100
c 2
l 65 -975 94 -889 159 100
c 2
l 94 -889 120 -800 154 100
c 2
l 120 -800 138 -726 148 100
c 2
l 138 -726 155 -647 143 100
c 2
l 155 -647 172 -565 138 100
c 2
l 172 -565 187 -482 132 100
c 2
l 187 -482 200 -400 127 100
c 2
l 200 -400 212 -320 122 100
c 2
l 212 -320 222 -240 116 100
c 2
l 222 -240 230 -160 111 100
c 2
l 230 -160 236 -80 105 100
c 2
l 236 -80 240 0 100 100
c 2
l 240 0 241 81 95 100
c 2
l 241 81 239 163 89 100
c 2
l 239 163 235 244 84 100
c 2
l 235 244 229 324 79 100
c 2
l 229 324 220 400 73 100
c 2
l 220 400 205 493 68 100
c 2
l 205 493 186 584 62 100
c 2
l 186 584 164 668 57 100
c 2
l 164 668 140 740 52 100
c 2
l 140 740 101 823 46 100
c 2
l 101 823 59 888 41 100
c 2
l 59 888 20 920 36 100
c 2
l 20 920 -31 880 30 100
c 2
l -31 880 -60 800 25 100
c 2
l -60 800 -35 723 19 100
c 2
l -35 723 0 660 14 100
c 3
d 5 -1048 49 85
c 3
d 63 -889 46 85
c 3
d 109 -726 43 85
c 3
d 146 -565 40 85
c 3
d 176 -400 36 85
c 3
d 200 -240 33 85
c 3
d 216 -80 30 85
c 3
d 223 81 27 85
c 3
d 219 244 24 85
c 3
d 206 400 20 85
c 3
d 175 584 17 85
c 3
d 131 740 14 85
c 3
d 52 888 12 85
c 3
d -36 880 12 85
c 3
d -38 723 12 85
]];
Figures.KrakenArmTL = [[
c 1
l -20 -1100 -38 -1048 200 100
c 1
l -38 -1048 -65 -975 195 100
c 1
l -65 -975 -94 -889 189 100
c 1
l -94 -889 -120 -800 184 100
c 1
l -120 -800 -138 -726 178 100
c 1
l -138 -726 -155 -647 173 100
c 1
l -155 -647 -172 -565 168 100
c 1
l -172 -565 -187 -482 162 100
c 1
l -187 -482 -200 -400 157 100
c 1
l -200 -400 -212 -320 152 100
c 1
l -212 -320 -222 -240 146 100
c 1
l -222 -240 -230 -160 141 100
c 1
l -230 -160 -236 -80 135 100
c 1
l -236 -80 -240 0 130 100
c 1
l -240 0 -241 81 125 100
c 1
l -241 81 -239 163 119 100
c 1
l -239 163 -235 244 114 100
c 1
l -235 244 -229 324 109 100
c 1
l -229 324 -220 400 103 100
c 1
l -220 400 -205 493 98 100
c 1
l -205 493 -186 584 92 100
c 1
l -186 584 -164 668 87 100
c 1
l -164 668 -140 740 82 100
c 1
l -140 740 -101 823 76 100
c 1
l -101 823 -59 888 71 100
c 1
l -59 888 -20 920 66 100
c 1
l -20 920 31 880 60 100
c 1
l 31 880 60 800 55 100
c 1
l 60 800 35 723 49 100
c 1
l 35 723 0 660 44 100
c 2
l -20 -1100 -38 -1048 170 100
c 2
l -38 -1048 -65 -975 165 100
c 2
l -65 -975 -94 -889 159 100
c 2
l -94 -889 -120 -800 154 100
c 2
l -120 -800 -138 -726 148 100
c 2
l -138 -726 -155 -647 143 100
c 2
l -155 -647 -172 -565 138 100
c 2
l -172 -565 -187 -482 132 100
c 2
l -187 -482 -200 -400 127 100
c 2
l -200 -400 -212 -320 122 100
c 2
l -212 -320 -222 -240 116 100
c 2
l -222 -240 -230 -160 111 100
c 2
l -230 -160 -236 -80 105 100
c 2
l -236 -80 -240 0 100 100
c 2
l -240 0 -241 81 95 100
c 2
l -241 81 -239 163 89 100
c 2
l -239 163 -235 244 84 100
c 2
l -235 244 -229 324 79 100
c 2
l -229 324 -220 400 73 100
c 2
l -220 400 -205 493 68 100
c 2
l -205 493 -186 584 62 100
c 2
l -186 584 -164 668 57 100
c 2
l -164 668 -140 740 52 100
c 2
l -140 740 -101 823 46 100
c 2
l -101 823 -59 888 41 100
c 2
l -59 888 -20 920 36 100
c 2
l -20 920 31 880 30 100
c 2
l 31 880 60 800 25 100
c 2
l 60 800 35 723 19 100
c 2
l 35 723 0 660 14 100
c 3
d -5 -1048 49 85
c 3
d -63 -889 46 85
c 3
d -109 -726 43 85
c 3
d -146 -565 40 85
c 3
d -176 -400 36 85
c 3
d -200 -240 33 85
c 3
d -216 -80 30 85
c 3
d -223 81 27 85
c 3
d -219 244 24 85
c 3
d -206 400 20 85
c 3
d -175 584 17 85
c 3
d -131 740 14 85
c 3
d -52 888 12 85
c 3
d 36 880 12 85
c 3
d 38 723 12 85
]];
Figures.VanCrest = [[
c 1
l 220 120 692 70 100 100
l 692 70 1165 21 59 100
c 2
l 220 120 692 70 70 100
l 692 70 1165 21 35 100
c 4
l 692 70 976 41 10 90
c 1
l 220 120 643 -34 100 100
l 643 -34 1066 -188 59 100
c 2
l 220 120 643 -34 70 100
l 643 -34 1066 -188 35 100
c 4
l 643 -34 897 -126 10 90
c 1
l 220 120 539 -104 95 100
l 539 -104 859 -327 57 100
c 2
l 220 120 539 -104 65 100
l 539 -104 859 -327 33 100
c 4
l 539 -104 731 -238 10 90
c 1
l 220 120 413 -110 90 100
l 413 -110 606 -340 54 100
c 2
l 220 120 413 -110 60 100
l 413 -110 606 -340 30 100
c 4
l 413 -110 529 -248 10 90
c 1
l -220 120 -692 70 100 100
l -692 70 -1165 21 59 100
c 2
l -220 120 -692 70 70 100
l -692 70 -1165 21 35 100
c 4
l -692 70 -976 41 10 90
c 1
l -220 120 -643 -34 100 100
l -643 -34 -1066 -188 59 100
c 2
l -220 120 -643 -34 70 100
l -643 -34 -1066 -188 35 100
c 4
l -643 -34 -897 -126 10 90
c 1
l -220 120 -539 -104 95 100
l -539 -104 -859 -327 57 100
c 2
l -220 120 -539 -104 65 100
l -539 -104 -859 -327 33 100
c 4
l -539 -104 -731 -238 10 90
c 1
l -220 120 -413 -110 90 100
l -413 -110 -606 -340 54 100
c 2
l -220 120 -413 -110 60 100
l -413 -110 -606 -340 30 100
c 4
l -413 -110 -529 -248 10 90
c 2
f 100 -50 -120 50 -120 60 -300 0 -520 -60 -300
c 1
p 1 14 100 -50 -120 50 -120 60 -300 0 -520 -60 -300
c 2
f 100 -200 -140 200 -140 200 100 120 300 0 400 -120 300 -200 100
c 1
p 1 24 100 -200 -140 200 -140 200 100 120 300 0 400 -120 300 -200 100
c 1
p 0 30 100 -120 -40 0 80 120 -40
p 0 20 80 -120 80 0 200 120 80
c 4
f 100 0 -100 45 -40 0 20 -45 -40
]];
Figures.ScaleBeam = [[
c 1
e 0 -300 100 100 20 100 0
l 0 -200 0 0 20 100
c 2
l -900 0 900 0 50 100
c 1
l -900 0 900 0 22 100
c 4
d 0 0 60 100
c 1
e 0 0 60 60 12 100 0
c 1
d -900 0 45 100
l -900 0 -900 80 20 100
c 4
d -900 0 18 100
c 1
d 900 0 45 100
l 900 0 900 80 20 100
c 4
d 900 0 18 100
c 3
d 0 -420 30 100
]];
Figures.ScalePan = [[
c 1
l 0 0 -300 520 10 90
l 0 0 300 520 10 90
l 0 0 0 520 10 70
c 2
f 100 -340 520 340 520 280 620 140 700 0 720 -140 700 -280 620
c 1
p 1 18 100 -340 520 340 520 280 620 140 700 0 720 -140 700 -280 620
c 3
l -300 550 300 550 10 60
c 4
d 0 450 45 95
]];
Figures.HolyCross = [[
c 4
l 328 -262 618 -184 12 55
c 4
l 240 -110 368 18 12 35
c 4
l 88 -22 166 268 12 55
c 4
l -88 -22 -135 152 12 35
c 4
l -240 -110 -453 103 12 55
c 4
l -328 -262 -502 -215 12 35
c 4
l -328 -438 -618 -516 12 55
c 4
l -240 -590 -368 -718 12 35
c 4
l -88 -678 -166 -968 12 55
c 4
l 88 -678 135 -852 12 35
c 4
l 240 -590 453 -803 12 55
c 4
l 328 -438 502 -485 12 35
c 2
f 100 -70 -1000 70 -1000 70 1000 -70 1000
f 100 -400 -450 400 -450 400 -270 -400 -270
c 1
p 1 16 100 -70 -1000 70 -1000 70 1000 -70 1000
p 1 16 100 -400 -450 400 -450 400 -270 -400 -270
c 3
l 0 -950 0 900 10 50
l -360 -360 360 -360 10 50
c 1
d 0 -1000 50 100
c 4
d 0 -1000 20 100
c 1
d 0 1000 50 100
c 4
d 0 1000 20 100
c 1
d -400 -360 50 100
c 4
d -400 -360 20 100
c 1
d 400 -360 50 100
c 4
d 400 -360 20 100
c 1
e 0 -360 120 120 14 100 0
c 4
d 0 -360 70 100
]];
Figures.HolyCloud = [[
c 2
b 0 180 800 70 30 0
c 3
b 0 50 900 200 96 0
b -520 -50 300 240 96 0
b -200 -200 340 280 96 0
b 200 -160 320 260 96 0
b 550 -20 280 200 96 0
b -850 60 200 140 96 0
b 880 80 200 140 96 0
c 1
e -520 -50 300 240 12 40 0
e -200 -200 340 280 12 40 0
e 200 -160 320 260 12 40 0
e 550 -20 280 200 12 40 0
c 4
d -100 -250 30 90
d 400 -120 22 80
]];
Figures.VanSword = [[
c 2
f 100 -40 -200 40 -200 36 -1860 0 -2000 -36 -1860
c 1
p 1 16 100 -40 -200 40 -200 36 -1860 0 -2000 -36 -1860
c 4
l 0 -260 0 -1800 12 90
c 3
l -26 -260 -22 -1800 8 50
c 1
l -150 -190 150 -190 40 100
l -150 -190 -180 -260 24 100
l 150 -190 180 -260 24 100
c 4
d 0 -190 34 100
c 2
l 0 -160 0 140 60 100
c 1
l -30 -100 30 -70 10 90
l -30 -30 30 0 10 90
l -30 40 30 70 10 90
l -30 110 30 140 10 90
c 1
d 0 200 50 100
c 4
d 0 200 20 100
]];
Figures.VanSwordL = [[
c 2
f 100 40 -200 -40 -200 -36 -1860 0 -2000 36 -1860
c 1
p 1 16 100 40 -200 -40 -200 -36 -1860 0 -2000 36 -1860
c 4
l 0 -260 0 -1800 12 90
c 3
l 26 -260 22 -1800 8 50
c 1
l 150 -190 -150 -190 40 100
l 150 -190 180 -260 24 100
l -150 -190 -180 -260 24 100
c 4
d 0 -190 34 100
c 2
l 0 -160 0 140 60 100
c 1
l 30 -100 -30 -70 10 90
l 30 -30 -30 0 10 90
l 30 40 -30 70 10 90
l 30 110 -30 140 10 90
c 1
d 0 200 50 100
c 4
d 0 200 20 100
]];
Figures.VanSpike = [[
c 1
l 0 0 295 -96 105 100
l 295 -96 590 -192 62 100
c 2
l 0 0 295 -96 75 100
l 295 -96 590 -192 38 100
c 4
l 295 -96 472 -153 10 90
c 1
l 0 0 247 -247 110 100
l 247 -247 495 -495 64 100
c 2
l 0 0 247 -247 80 100
l 247 -247 495 -495 40 100
c 4
l 247 -247 396 -396 10 90
c 1
l 0 0 87 -266 100 100
l 87 -266 173 -533 59 100
c 2
l 0 0 87 -266 70 100
l 87 -266 173 -533 35 100
c 4
l 87 -266 138 -426 10 90
c 2
d 0 0 100 100
c 1
e 0 0 100 100 20 100 0
c 4
d 0 0 40 100
]];
Figures.VanSpikeL = [[
c 1
l 0 0 -295 -96 105 100
l -295 -96 -590 -192 62 100
c 2
l 0 0 -295 -96 75 100
l -295 -96 -590 -192 38 100
c 4
l -295 -96 -472 -153 10 90
c 1
l 0 0 -247 -247 110 100
l -247 -247 -495 -495 64 100
c 2
l 0 0 -247 -247 80 100
l -247 -247 -495 -495 40 100
c 4
l -247 -247 -396 -396 10 90
c 1
l 0 0 -87 -266 100 100
l -87 -266 -173 -533 59 100
c 2
l 0 0 -87 -266 70 100
l -87 -266 -173 -533 35 100
c 4
l -87 -266 -138 -426 10 90
c 2
d 0 0 100 100
c 1
e 0 0 100 100 20 100 0
c 4
d 0 0 40 100
]];
Figures.VanSpikeB = [[
c 1
l 0 0 295 96 105 100
l 295 96 590 192 62 100
c 2
l 0 0 295 96 75 100
l 295 96 590 192 38 100
c 4
l 295 96 472 153 10 90
c 1
l 0 0 247 247 110 100
l 247 247 495 495 64 100
c 2
l 0 0 247 247 80 100
l 247 247 495 495 40 100
c 4
l 247 247 396 396 10 90
c 1
l 0 0 87 266 100 100
l 87 266 173 533 59 100
c 2
l 0 0 87 266 70 100
l 87 266 173 533 35 100
c 4
l 87 266 138 426 10 90
c 2
d 0 0 100 100
c 1
e 0 0 100 100 20 100 0
c 4
d 0 0 40 100
]];
Figures.VanSpikeBL = [[
c 1
l 0 0 -295 96 105 100
l -295 96 -590 192 62 100
c 2
l 0 0 -295 96 75 100
l -295 96 -590 192 38 100
c 4
l -295 96 -472 153 10 90
c 1
l 0 0 -247 247 110 100
l -247 247 -495 495 64 100
c 2
l 0 0 -247 247 80 100
l -247 247 -495 495 40 100
c 4
l -247 247 -396 396 10 90
c 1
l 0 0 -87 266 100 100
l -87 266 -173 533 59 100
c 2
l 0 0 -87 266 70 100
l -87 266 -173 533 35 100
c 4
l -87 266 -138 426 10 90
c 2
d 0 0 100 100
c 1
e 0 0 100 100 20 100 0
c 4
d 0 0 40 100
]];

-- rigs: how the parts of a figure hang together and move (see RigPose)
local Rigs = {};
Rigs.Guardian = [[
j base - 0 900 0 0 0 0
j halo base 0 -500 -679 -1179 679 179
j rune base 0 950 -876 74 876 1826
j orbit base 0 -200 -1050 -1250 1050 850
j wR1 torso 200 -500 120 -860 1003 -419
j wR2 torso 200 -500 120 -1109 870 -419
j wR3 torso 200 -500 122 -1178 589 -422
j wR4 torso 200 -500 127 -1068 347 -427
j wL1 torso -200 -500 -1002 -860 -120 -419
j wL2 torso -200 -500 -869 -1109 -120 -419
j wL3 torso -200 -500 -588 -1178 -122 -422
j wL4 torso -200 -500 -347 -1068 -127 -427
j legR base 170 300 24 263 456 1006
j legL base -170 300 -456 263 -24 1006
j torso base 0 120 -288 -538 288 536
j core torso 0 -300 -124 -424 124 -176
j neck torso 0 -520 -156 -586 156 -454
j finR helm 130 -760 84 -1026 346 -704
j finL helm -130 -760 -346 -1026 -84 -704
j helm torso 0 -560 -173 -1086 173 -502
j visor helm 0 -700 -139 -759 139 -654
j uarmR torso 470 -380 333 -397 587 17
j farmR uarmR 430 0 293 -207 677 65
j pauldR torso 300 -500 82 -770 680 -174
j pauldL torso -300 -500 -680 -770 -82 -174
j sword farmR 620 -100 391 -1056 849 90
j shield torso -500 -320 -1005 -575 -355 705
i halo s 5000 100 0 10
i rune a 400 340 0 10
i orbit s -8000 100 0 10
i wR1 r 2200 420 0 10
i wR2 r 2750 470 170 10
i wR3 r 3300 520 340 10
i wR4 r 3850 570 510 10
i wL1 r -2200 420 500 10
i wL2 r -2750 470 670 10
i wL3 r -3300 520 840 10
i wL4 r -3850 570 1010 10
i legR r 450 540 0 10
i legL r 450 540 500 10
i torso r 900 460 0 10
i torso y 12 460 250 10
i core a 500 220 0 10
i finR r 2600 320 100 10
i finL r -2600 320 600 10
i helm r 1300 520 300 10
i helm y 6 520 550 10
i visor a 400 260 200 10
i uarmR r 1400 460 50 10
i farmR r 2200 460 120 10
i pauldR r 900 410 200 10
i pauldL r -900 410 700 10
i sword r 2200 630 200 10
i sword r 15000 920 380 50
i shield r 1700 510 100 10
i shield y 12 370 300 10
k halo 0 0 -14 -8
k orbit 0 0 6 4
k torso 2200 0 8 0
k helm 6500 3500 12 6
k visor 0 0 20 12
k shield 0 0 18 10
r wR1 9000 0 0 0
r wR2 8000 4 0 0
r wR3 7000 8 0 0
r wR4 6000 12 0 0
r wL1 -9000 0 0 0
r wL2 -8000 4 0 0
r wL3 -7000 8 0 0
r wL4 -6000 12 0 0
r torso -2600 5 0 20
r finR 7000 14 0 0
r finL -7000 14 0 0
r helm 5000 12 0 0
r uarmR -11000 0 0 0
r farmR -24000 5 0 0
r pauldR 3500 6 0 0
r pauldL -3500 6 0 0
r sword 40000 10 0 0
r shield -6000 10 -12 20
e 1 ring core 0 -300 1 1
e 1 slash sword 620 -600 4 1
e 1 spark sword 620 -1000 4 10
e 0 spark sword 620 -1000 4 4
e 1 streak torso 0 -300 3 7
]];
Rigs.Angel = [[
j base - 0 900 0 0 0 0
j wingRo wingR 100 -460 -164 -1200 1030 44
j wingR torso 100 -460 -51 -1048 710 -131
j wingLo wingL -100 -460 -1030 -1200 164 44
j wingL torso -100 -460 -710 -1048 51 -131
j cloudSideL base -700 980 -950 750 -470 1240
j cloudSideR base 720 960 510 730 990 1220
j cloud base 0 1000 -720 390 730 1650
j mist base 0 1050 -630 720 630 1480
j robe torso 0 -300 -467 -657 467 987
j torso base 0 100 0 0 0 0
j sleeveR torso 100 -560 44 -636 536 -124
j sleeveL torso -100 -560 -536 -636 -44 -124
j light sleeveR 480 -260 356 -384 604 -136
j hair head 0 -800 -184 -884 184 -286
j head torso 0 -620 -113 -833 113 -607
j halo head 0 -890 -168 -1058 168 -722
j sparkles base 0 -300 -890 -1090 895 375
i base y 30 440 0 10
i base y 12 230 300 10
i base x 10 670 100 10
i wingRo r 3200 440 140 10
i wingRo r 9000 880 520 30
i wingR r 2200 440 0 10
i wingR r 5000 880 500 30
i wingLo r -3200 440 140 10
i wingLo r -9000 880 550 30
i wingL r -2200 440 0 10
i wingL r -5000 880 530 30
i cloudSideL x 50 930 0 10
i cloudSideL y 12 510 300 10
i cloudSideL a 250 620 100 10
i cloudSideR x -50 1110 400 10
i cloudSideR y 12 570 600 10
i cloudSideR a 250 730 500 10
i cloud x 20 740 100 10
i cloud y 12 440 300 10
i mist x 80 810 200 10
i mist a 500 530 0 10
i robe r 1400 440 250 10
i robe x 10 440 500 10
i torso r 800 440 0 10
i sleeveR r -2400 390 0 10
i sleeveL r 2400 390 500 10
i light y -20 260 0 10
i light a 400 190 200 10
i hair r 2400 360 0 10
i hair x 6 360 300 10
i head r 1200 490 300 10
i halo y 8 310 0 10
i halo a 350 240 0 10
i sparkles a 700 210 0 10
i sparkles r 4000 650 0 10
k torso 1600 0 6 0
k head 6000 3500 10 6
r wingRo 14000 6 0 0
r wingR 8000 0 0 0
r wingLo -14000 6 0 0
r wingL -8000 0 0 0
r cloud 0 0 0 20
r robe 2000 10 0 0
r torso -1500 4 0 12
r sleeveR 11000 3 0 0
r sleeveL -11000 3 0 0
r light 0 0 0 -30
r hair 4000 14 0 0
r head 3000 10 0 0
r halo 0 0 0 -25
e 1 petal wingRo 500 -800 3 7
e 1 petal wingLo -500 -800 3 7
e 0 petal wingRo 500 -800 3 3
e 1 ring halo 0 -890 4 1
e 1 spark light 480 -260 4 8
]];
Rigs.Ship = [[
j base - 0 600 0 0 0 0
j mizzen hull 500 -580 464 -616 916 156
j jib hull -520 -620 -1006 -656 -484 156
j foreSails hull -500 -720 -796 -736 -204 -104
j mainSails hull 0 -960 -496 -976 496 36
j sigil mainSails 0 -270 -157 -436 157 -104
j masts hull 0 200 -1003 -1014 874 244
j pennantA masts 0 -990 -34 -1024 254 -866
j pennantB masts -500 -720 -534 -754 -266 -606
j hull base 0 580 -1011 -100 900 700
j lamps hull 0 300 -916 -160 920 374
j sea1 base 0 720 -1138 653 1138 787
j sea2 base 0 820 -1136 749 1136 891
j sea3 base 0 920 -1136 855 1136 985
j foam base 0 700 -985 585 746 786
i mizzen r 1800 340 0 10
i jib r -1800 310 300 10
i foreSails r 1300 370 200 10
i mainSails r 1100 410 500 10
i mainSails x 6 410 100 10
i sigil a 450 270 0 10
i pennantA r 9000 110 0 10
i pennantA r 4000 47 300 10
i pennantB r 9000 130 400 10
i pennantB r 4000 53 100 10
i hull r 1700 620 0 10
i hull r 600 270 300 10
i hull y 20 410 200 10
i lamps a 500 160 0 10
i lamps a 250 60 400 10
i sea1 x 100 530 0 10
i sea1 y 12 310 0 10
i sea2 x -120 670 300 10
i sea2 y 14 370 300 10
i sea3 x 80 440 600 10
i sea3 y 12 290 600 10
i foam x 60 330 0 10
i foam y 15 210 0 10
i foam a 400 190 200 10
r mizzen 4000 5 0 0
r jib -4000 4 0 0
r foreSails 3000 7 0 0
r mainSails 3500 6 0 0
r pennantA 16000 5 0 0
r pennantB 16000 8 0 0
r hull -3200 2 0 20
e 1 spark foam -900 660 3 10
e 0 spark foam -900 660 3 4
e 1 ring sigil 0 -270 4 1
e 1 bubble foam 400 720 3 5
]];
Rigs.Kraken = [[
j base - 0 0 0 0 0 0
j aR0_3 aR0_2 810 -610 594 -732 857 -520
j aR0_2 aR0_1 760 -200 705 -658 900 -145
j aR0_1 aR0_0 504 90 441 -256 817 153
j aR0_0 head 120 60 48 -12 569 216
j aR1_3 aR1_2 900 300 680 148 947 347
j aR1_2 aR1_1 640 540 584 251 949 596
j aR1_1 aR1_0 318 366 251 299 699 604
j aR1_0 head 100 100 24 24 387 436
j aR2_3 aR2_2 730 790 683 540 891 837
j aR2_2 aR2_1 440 780 384 724 779 882
j aR2_1 aR2_0 201 464 134 397 499 839
j aR2_0 head 70 120 -6 44 271 534
j aR3_3 aR3_2 479 931 432 740 617 979
j aR3_2 aR3_1 194 804 137 747 529 1000
j aR3_1 aR3_0 83 505 16 438 254 864
j aR3_0 head 40 130 -36 54 152 574
j aL0_3 aL0_2 -810 -610 -856 -732 -592 -520
j aL0_2 aL0_1 -760 -200 -899 -658 -705 -145
j aL0_1 aL0_0 -504 90 -816 -256 -441 153
j aL0_0 head -120 60 -569 -12 -48 216
j aL1_3 aL1_2 -900 300 -947 148 -680 347
j aL1_2 aL1_1 -640 540 -949 251 -584 596
j aL1_1 aL1_0 -318 366 -698 299 -251 604
j aL1_0 head -100 100 -387 24 -24 436
j aL2_3 aL2_2 -730 790 -890 540 -683 837
j aL2_2 aL2_1 -440 780 -779 724 -384 882
j aL2_1 aL2_0 -201 464 -499 397 -133 839
j aL2_0 head -70 120 -270 44 6 534
j aL3_3 aL3_2 -479 931 -617 740 -431 979
j aL3_2 aL3_1 -194 804 -528 747 -137 1000
j aL3_1 aL3_0 -83 505 -253 438 -16 864
j aL3_0 head -40 130 -152 54 37 574
j head base 0 -50 -290 -1000 290 85
j finR head 120 -680 63 -957 457 -523
j finL head -120 -680 -457 -957 -63 -523
j irisR head 145 -40 60 -125 230 45
j irisL head -145 -40 -230 -125 -60 45
j lids head 0 -40 -277 -177 277 92
j beak head 0 60 -86 24 86 206
j lights head 0 -400 -194 -864 194 -128
j bubbles base 0 0 -674 -858 608 1012
i base x 100 2900 0 10
i base x 40 1370 300 10
i base y 70 2100 100 10
i base y 25 930 600 10
i base r 1600 3700 200 10
i base r 700 1700 700 10
i aR0_3 r 8300 640 -360 10
i aR0_2 r 6400 640 -240 10
i aR0_1 r 4500 640 -120 10
i aR0_0 r 2600 640 0 10
i aR1_3 r 8300 695 -170 10
i aR1_2 r 6400 695 -50 10
i aR1_1 r 4500 695 70 10
i aR1_0 r 2600 695 190 10
i aR2_3 r 8300 750 20 10
i aR2_2 r 6400 750 140 10
i aR2_1 r 4500 750 260 10
i aR2_0 r 2600 750 380 10
i aR3_3 r 8300 805 210 10
i aR3_2 r 6400 805 330 10
i aR3_1 r 4500 805 450 10
i aR3_0 r 2600 805 570 10
i aL0_3 r -8300 720 10 10
i aL0_2 r -6400 720 130 10
i aL0_1 r -4500 720 250 10
i aL0_0 r -2600 720 370 10
i aL1_3 r -8300 775 200 10
i aL1_2 r -6400 775 320 10
i aL1_1 r -4500 775 440 10
i aL1_0 r -2600 775 560 10
i aL2_3 r -8300 830 390 10
i aL2_2 r -6400 830 510 10
i aL2_1 r -4500 830 630 10
i aL2_0 r -2600 830 750 10
i aL3_3 r -8300 885 580 10
i aL3_2 r -6400 885 700 10
i aL3_1 r -4500 885 820 10
i aL3_0 r -2600 885 940 10
i head r 1300 810 0 10
i head y 14 610 200 10
i finR r 4500 460 0 10
i finL r -4500 460 400 10
i lids y 4 330 0 10
i beak r 4000 370 0 10
i beak y 6 370 250 10
i lights a 550 310 0 10
i lights a 300 170 400 10
i bubbles y -60 1100 0 10
i bubbles a 500 430 200 10
k head 3000 1500 12 6
k irisR 0 0 26 20
k irisL 0 0 26 20
r aR0_3 12700 18 0 0
r aR0_2 10300 12 0 0
r aR0_1 7900 6 0 0
r aR0_0 5500 0 0 0
r aR1_3 12700 20 0 0
r aR1_2 10300 14 0 0
r aR1_1 7900 8 0 0
r aR1_0 5500 2 0 0
r aR2_3 12700 22 0 0
r aR2_2 10300 16 0 0
r aR2_1 7900 10 0 0
r aR2_0 5500 4 0 0
r aR3_3 12700 24 0 0
r aR3_2 10300 18 0 0
r aR3_1 7900 12 0 0
r aR3_0 5500 6 0 0
r aL0_3 -12700 18 0 0
r aL0_2 -10300 12 0 0
r aL0_1 -7900 6 0 0
r aL0_0 -5500 0 0 0
r aL1_3 -12700 20 0 0
r aL1_2 -10300 14 0 0
r aL1_1 -7900 8 0 0
r aL1_0 -5500 2 0 0
r aL2_3 -12700 22 0 0
r aL2_2 -10300 16 0 0
r aL2_1 -7900 10 0 0
r aL2_0 -5500 4 0 0
r aL3_3 -12700 24 0 0
r aL3_2 -10300 18 0 0
r aL3_1 -7900 12 0 0
r aL3_0 -5500 6 0 0
r head 0 0 0 30
r finR 9000 8 0 0
r finL -9000 8 0 0
r beak 0 0 0 20
e 1 bubble beak 0 160 3 7
e 0 bubble beak 0 160 3 3
e 1 ring head 0 -40 4 1
e 1 spark aR0_3 640 -560 4 6
e 1 spark aL0_3 -640 -560 4 6
]];
Rigs.Phoenix = [[
j base - 0 400 0 0 0 0
j tailA_2 tailA_1 -100 700 -148 652 36 1036
j tailA_1 tailA_0 60 400 -152 336 124 752
j tailA_0 body 0 100 -80 20 131 468
j tailB_2 tailB_1 400 580 304 534 448 916
j tailB_1 tailB_0 200 360 141 301 450 630
j tailB_0 body 40 100 -32 28 263 423
j tailC_2 tailC_1 -400 580 -448 534 -304 916
j tailC_1 tailC_0 -200 360 -449 301 -141 630
j tailC_0 body -40 100 -262 28 33 423
j tailD_2 tailD_1 640 400 597 357 735 735
j tailD_1 tailD_0 340 240 286 186 686 446
j tailD_0 body 80 80 15 15 397 297
j tailE_2 tailE_1 -640 400 -735 357 -597 735
j tailE_1 tailE_0 -340 240 -686 186 -286 446
j tailE_0 body -80 80 -397 15 -15 297
j wingRo wingR 100 -200 -266 -1095 1039 282
j wingR body 100 -200 -125 -795 775 145
j wingLo wingL -100 -200 -1039 -1095 266 282
j wingL body -100 -200 -775 -795 125 145
j body base 0 -120 -317 -437 317 357
j heart body 0 0 -65 -65 65 65
j neck body 0 -280 -91 -585 111 -195
j head neck 20 -500 -195 -702 142 -458
j crestA_1 crestA_0 -36 -844 -194 -1014 7 -801
j crestA_0 head 20 -640 -82 -890 75 -585
j crestB_1 crestB_0 148 -857 106 -974 334 -815
j crestB_0 head 40 -640 -12 -902 193 -587
j crestC_1 crestC_0 40 -820 -2 -1054 94 -777
j crestC_0 head 20 -640 -35 -866 87 -585
j sparks base 0 -100 -890 -670 950 670
i base y 40 340 0 10
i base y 12 130 300 10
i base x 15 590 200 10
i base r 800 510 0 10
i tailA_2 r 7680 280 -260 10
i tailA_1 r 5440 280 -130 10
i tailA_0 r 3200 280 0 10
i tailB_2 r 8400 310 -60 10
i tailB_1 r 5950 310 70 10
i tailB_0 r 3500 310 200 10
i tailC_2 r -8400 310 290 10
i tailC_1 r -5950 310 420 10
i tailC_0 r -3500 310 550 10
i tailD_2 r 9120 340 140 10
i tailD_1 r 6460 340 270 10
i tailD_0 r 3800 340 400 10
i tailE_2 r -9120 340 540 10
i tailE_1 r -6460 340 670 10
i tailE_0 r -3800 340 800 10
i wingRo r 5500 310 170 10
i wingRo r 14000 820 200 30
i wingR r 3500 310 0 10
i wingR r 8000 820 180 30
i wingLo r -5500 310 170 10
i wingLo r -14000 820 230 30
i wingL r -3500 310 0 10
i wingL r -8000 820 210 30
i body r 1000 340 0 10
i body y 10 170 200 10
i heart a 500 110 0 10
i heart a 250 43 100 10
i neck r 2000 410 0 10
i head r 2000 370 300 10
i crestA_1 r 8500 190 -30 10
i crestA_0 r 5000 190 100 10
i crestB_1 r -8500 220 370 10
i crestB_0 r -5000 220 500 10
i crestC_1 r 6800 170 670 10
i crestC_0 r 4000 170 800 10
i sparks y -90 360 0 10
i sparks a 700 180 300 10
k body 1500 0 6 0
k neck 3000 2000 6 0
k head 5000 3000 10 6
r tailA_2 11520 10 0 0
r tailA_1 8640 5 0 0
r tailA_0 5760 0 0 0
r tailB_2 12600 10 0 0
r tailB_1 9450 5 0 0
r tailB_0 6300 0 0 0
r tailC_2 -12600 10 0 0
r tailC_1 -9450 5 0 0
r tailC_0 -6300 0 0 0
r tailD_2 13680 10 0 0
r tailD_1 10260 5 0 0
r tailD_0 6840 0 0 0
r tailE_2 -13680 10 0 0
r tailE_1 -10260 5 0 0
r tailE_0 -6840 0 0 0
r wingRo 20000 6 0 0
r wingR 11000 0 0 0
r wingLo -20000 6 0 0
r wingL -11000 0 0 0
r body -2000 3 0 20
r neck 3000 6 0 0
r head 4000 10 0 0
r crestA_1 13500 5 0 0
r crestA_0 9000 0 0 0
r crestB_1 -13500 5 0 0
r crestB_0 -9000 0 0 0
r crestC_1 10800 5 0 0
r crestC_0 7200 0 0 0
e 1 spark wingRo 700 -950 3 9
e 1 spark wingLo -700 -950 3 9
e 0 spark heart 0 0 3 4
e 1 ring heart 0 0 3 1
e 1 streak head 100 -950 3 8
]];
Rigs.Kitsune = [[
j base - 0 900 0 0 0 0
j tail0 torso 0 400 -839 -92 40 780
j tail1 torso 0 400 -817 -232 79 665
j tail2 torso 0 400 -762 -362 160 560
j tail3 torso 0 400 -669 -465 278 482
j tail4 torso 0 400 -549 -540 423 440
j tail5 torso 0 400 -393 -509 554 444
j tail6 torso 0 400 -255 -433 667 489
j tail7 torso 0 400 -144 -327 753 570
j tail8 torso 0 400 -71 -199 801 673
j torso base 0 600 -517 23 517 1011
j earR head 200 -200 63 -677 337 -143
j earL head -200 -200 -337 -677 -63 -143
j head torso 0 100 -338 -338 338 314
j branchL base -950 -440 -986 -956 -364 -424
j branchR base 950 -400 464 -936 986 -364
j petals base 0 0 -935 -815 955 835
i tail0 r 4200 460 0 10
i tail0 r 1200 230 0 10
i tail1 r 3750 485 110 10
i tail1 r 1200 230 200 10
i tail2 r 3300 510 220 10
i tail2 r 1200 230 400 10
i tail3 r 2850 535 330 10
i tail3 r 1200 230 600 10
i tail4 r 2400 560 440 10
i tail4 r 1200 230 800 10
i tail5 r 2850 585 550 10
i tail5 r 1200 230 1000 10
i tail6 r 3300 610 660 10
i tail6 r 1200 230 1200 10
i tail7 r 3750 635 770 10
i tail7 r 1200 230 1400 10
i tail8 r 4200 660 880 10
i tail8 r 1200 230 1600 10
i torso r 600 420 0 10
i torso y 8 420 250 10
i earR r 1200 340 0 10
i earR r -9000 630 300 60
i earL r -1200 340 500 10
i earL r 9000 810 700 60
i head r 1400 510 200 10
i head y 6 510 450 10
i branchL r 2200 480 0 10
i branchR r -2200 530 400 10
i petals y 50 730 0 10
i petals x 30 910 300 10
i petals r 6000 820 0 10
i petals a 400 370 200 10
k torso 1200 0 6 0
k head 6000 4000 12 8
r tail0 -9600 10 0 0
r tail1 -7200 8 0 0
r tail2 -4800 5 0 0
r tail3 -2400 3 0 0
r tail4 0 0 0 0
r tail5 2400 3 0 0
r tail6 4800 5 0 0
r tail7 7200 8 0 0
r tail8 9600 10 0 0
r torso -1600 4 0 12
r earR -7000 5 0 0
r earL 7000 5 0 0
r head 3000 10 0 -12
r branchL -5000 10 0 0
r branchR 5000 10 0 0
e 1 petal branchL -600 -780 4 8
e 1 petal branchR 660 -760 4 8
e 0 petal branchR 660 -760 4 3
e 1 spark tail4 0 -400 3 8
e 1 ring head 0 -200 4 1
]];
Rigs.Reaper = [[
j base - 0 900 0 0 0 0
j scythe handR 500 -200 -556 -1076 622 1002
j hem cloak 0 120 -618 46 618 1008
j cloak torso 0 -500 -436 -938 436 453
j torso base 0 100 0 0 0 0
j hood torso 0 -560 -144 -854 144 -506
j eyes hood 0 -660 -109 -714 109 -596
j handR armR 460 -200 444 -256 577 -48
j armR torso 260 -440 180 -535 540 -120
j armL torso -260 -440 -480 -520 -180 -20
j fire0 base -700 342 -800 151 -600 400
j fire1 base -550 680 -630 535 -470 730
j fire2 base 780 536 690 368 870 590
j fire3 base -820 -173 -895 -306 -745 -125
j fire4 base 700 -470 620 -615 780 -420
i base y 30 480 0 10
i base y 10 220 400 10
i base x 12 710 200 10
i scythe r 1800 560 0 10
i scythe r -9000 890 350 40
i hem r 3500 390 250 10
i hem x 20 390 550 10
i cloak r 900 480 0 10
i cloak y 10 480 250 10
i hood r 1300 540 100 10
i eyes a 500 210 0 10
i eyes a 250 67 300 10
i handR r 2000 430 200 10
i armR r 1500 490 0 10
i armL r 2400 410 400 10
i fire0 y -40 310 0 10
i fire0 x 15 430 0 10
i fire0 r 7000 120 0 10
i fire0 a 500 190 0 10
i fire1 y -50 370 170 10
i fire1 x 15 480 300 10
i fire1 r 7000 140 100 10
i fire1 a 500 220 200 10
i fire2 y -60 430 340 10
i fire2 x 15 530 600 10
i fire2 r 7000 160 200 10
i fire2 a 500 250 400 10
i fire3 y -70 490 510 10
i fire3 x 15 580 900 10
i fire3 r 7000 180 300 10
i fire3 a 500 280 600 10
i fire4 y -80 550 680 10
i fire4 x 15 630 1200 10
i fire4 r 7000 200 400 10
i fire4 a 500 310 800 10
k torso 1800 0 8 0
k hood 6000 4000 12 8
k eyes 0 0 18 10
r scythe 26000 8 0 0
r hem 6000 12 0 0
r cloak -2000 4 0 0
r hood 4000 10 0 0
r handR 6000 8 0 0
r armR -6000 3 0 0
r armL 5000 5 0 0
r fire0 0 0 0 -40
r fire1 0 0 0 -40
r fire2 0 0 0 -40
r fire3 0 0 0 -40
r fire4 0 0 0 -40
e 1 slash scythe 0 -900 4 1
e 1 streak scythe -450 -600 4 8
e 0 spark scythe -450 -600 4 4
e 1 ring eyes 0 -660 4 1
e 1 spark fire2 780 500 4 6
]];
Rigs.Mecha = [[
j base - 0 400 0 0 0 0
j thrR torso 330 -500 184 -936 476 -414
j thrRf thrR 380 -800 334 -896 426 -584
j thrL torso -330 -500 -476 -936 -184 -414
j thrLf thrL -380 -800 -426 -896 -334 -584
j armRf armR 700 620 563 583 857 994
j armR torso 700 -100 503 -137 917 657
j armLf armL -700 620 -857 583 -563 994
j armL torso -700 -100 -917 -137 -503 657
j torso base 0 300 -538 -438 538 738
j spokes torso 0 50 -225 -150 225 250
j core torso 0 50 -110 -60 110 160
j circuits torso 0 100 -384 -194 384 264
j pauldR torso 500 -300 322 -498 978 36
j pauldL torso -500 -300 -978 -498 -322 36
j neck torso 0 -400 -136 -556 136 -364
j antR head 180 -800 140 -1040 390 -760
j antL head -180 -800 -390 -1040 -140 -760
j head torso 0 -420 -309 -977 309 -341
j visor head 0 -630 -244 -714 244 -546
j sparks base 0 -100 -946 -786 946 446
i base y 20 390 0 10
i base y 7 130 300 10
i base x 8 610 200 10
i thrR r 1500 330 0 10
i thrRf a 600 31 0 10
i thrRf a 300 83 500 10
i thrL r -1500 330 500 10
i thrLf a 600 31 0 10
i thrLf a 300 83 500 10
i armRf r 1600 360 200 10
i armR r 1200 440 0 10
i armLf r -1600 360 700 10
i armL r -1200 440 500 10
i torso r 700 470 0 10
i torso y 10 390 300 10
i spokes s 38000 100 0 10
i core a 550 140 0 10
i core a 200 50 300 10
i circuits a 700 190 0 10
i circuits a 300 70 400 10
i pauldR r 1000 410 300 10
i pauldR y 8 320 200 10
i pauldL r -1000 410 800 10
i pauldL y 8 320 200 10
i neck r 2000 290 0 10
i antR r 7000 190 0 10
i antR r 2500 80 200 10
i antL r -7000 190 350 10
i antL r -2500 80 200 10
i head r 1200 450 300 10
i visor a 300 170 0 10
i sparks a 800 120 0 10
i sparks y 30 270 0 10
k torso 1400 0 8 0
k head 9000 5000 14 8
k visor 0 0 34 14
r thrR 4000 5 0 0
r thrL -4000 5 0 0
r armRf -3000 4 0 -45
r armR -4000 2 0 0
r armLf 3000 4 0 -45
r armL 4000 2 0 0
r torso -1800 3 0 15
r spokes 40000 0 0 0
r pauldR 5000 5 0 -20
r pauldL -5000 5 0 -20
r antR 24000 4 0 0
r antL -24000 4 0 0
r head 5000 8 0 0
e 1 streak armRf 710 960 4 7
e 1 streak armLf -710 960 4 7
e 0 spark armRf 710 960 4 3
e 1 ring core 0 50 4 1
e 1 spark antR 340 -990 4 6
e 1 spark antL -340 -990 4 6
]];

local FigureCache = {};

local function DecodeFigure(Name)
	local Cached = FigureCache[Name];
	if Cached then
		return Cached;
	end;

	local Source = Figures[Name];
	if not Source then
		return nil;
	end;

	local List = {};

	for Line in string.gmatch(Source, '[^\n]+') do
		local T = {};
		for Token in string.gmatch(Line, '%S+') do
			T[#T + 1] = Token;
		end;

		local K = T[1];
		local function N(I, Div)
			return (tonumber(T[I]) or 0) / Div;
		end;
		local function Points(From)
			local Pts = {};
			for I = From, #T - 1, 2 do
				Pts[#Pts + 1] = { tonumber(T[I]) / 1000, tonumber(T[I + 1]) / 1000 };
			end;
			return Pts;
		end;

		if K == 'c' then
			List[#List + 1] = { 'c', tonumber(T[2]) };
		elseif K == 'g' then
			List[#List + 1] = { 'g', T[2] };
		elseif K == 'l' then
			List[#List + 1] = { 'line', N(2, 1000), N(3, 1000), N(4, 1000), N(5, 1000), N(6, 1000), N(7, 100) };
		elseif K == 'p' then
			List[#List + 1] = { 'poly', Points(5), T[2] == '1', N(3, 1000), N(4, 100) };
		elseif K == 'f' then
			List[#List + 1] = { 'fill', Points(3), N(2, 100) };
		elseif K == 'd' then
			List[#List + 1] = { 'dot', N(2, 1000), N(3, 1000), N(4, 1000), N(5, 100) };
		elseif K == 'e' then
			List[#List + 1] = { 'ell', N(2, 1000), N(3, 1000), N(4, 1000), N(5, 1000), N(6, 1000), N(7, 100), N(8, 10) };
		elseif K == 'b' then
			List[#List + 1] = { 'blob', N(2, 1000), N(3, 1000), N(4, 1000), N(5, 1000), N(6, 100), N(7, 10) };
		elseif K == 'r' then
			List[#List + 1] = { 'ring', N(2, 1000), N(3, 1000), N(4, 100) };
		end;
	end;

	FigureCache[Name] = List;
	return List;
end;

-- [[rig:decode]]
-- ---------------------------------------------------------------- rigs
-- A rigged figure is cut into parts (the g lines of its command list: everything up to the next g is one part, the order is the drawing
-- order). Its rig says how the parts hang together and how they move (the pose maths is the same as rigPose in the store preview):
--   j id parent px py x0 y0 x1 y1     a part: its pivot and the box around its drawing ('-' = no parent)
--   i id ch amp period phase pow      an idle wave. ch: r = turn (degrees), x / y = slide, a = fade (0..1), s = spin (degrees per second)
--   k id kx ky tx ty                  how far it turns / slides with the pointer (the pointer is -1..1 from the figure's centre)
--   r id amp delay tx ty              the kick of a tab change or a pressed control (delay: seconds, so a kick can travel along a chain)
--   e level kind part x y slot n      a small effect at the kick (level 0 = also for a pressed control)
-- numbers are integers: x1000 (period and delay x100, pow x10)
local RigCache = {};

local function DecodeRig(Name)
	local Cached = RigCache[Name];
	if Cached ~= nil then
		return Cached or nil;
	end;

	local Source = Rigs[Name];
	if not Source then
		RigCache[Name] = false;
		return nil;
	end;

	local Rig = { Parts = {}; Index = {}; Order = {}; Fx = {}; };
	local Parents = {};

	for Line in string.gmatch(Source, '[^\n]+') do
		local T = {};
		for Token in string.gmatch(Line, '%S+') do
			T[#T + 1] = Token;
		end;

		local K = T[1];
		local function N(I, Div)
			return (tonumber(T[I]) or 0) / (Div or 1000);
		end;

		if K == 'j' then
			table.insert(Rig.Parts, { Id = T[2]; Parent = 0; PX = N(4); PY = N(5); Box = { N(6), N(7), N(8), N(9) }; Idle = {}; });
			Rig.Index[T[2]] = #Rig.Parts;
			Parents[#Rig.Parts] = T[3];
		else
			local Part = Rig.Parts[Rig.Index[T[2]] or 0];

			if K == 'i' and Part then
				table.insert(Part.Idle, { Ch = T[3]; Amp = N(4); Period = math.max(N(5, 100), 0.05); Phase = N(6); Pow = N(7, 10); });
			elseif K == 'k' and Part then
				Part.Look = { KX = N(3); KY = N(4); TX = N(5); TY = N(6); };
			elseif K == 'r' and Part then
				Part.React = { Amp = N(3); Delay = N(4, 100); TX = N(5); TY = N(6); };
			elseif K == 'e' then
				table.insert(Rig.Fx, {
					Level = tonumber(T[2]) or 0; Kind = T[3]; Part = Rig.Index[T[4]] or 1; X = N(5); Y = N(6);
					Slot = tonumber(T[7]) or 4; N = tonumber(T[8]) or 6;
				});
			end;
		end;
	end;

	for I, Id in ipairs(Parents) do
		Rig.Parts[I].Parent = Id ~= '-' and Rig.Index[Id] or 0;
	end;

	-- parents before children (the drawing order is another thing: a wing is drawn behind the body it hangs from)
	local Seen = {};
	local function Visit(I)
		if Seen[I] then
			return;
		end;
		Seen[I] = true;

		local Parent = Rig.Parts[I].Parent;
		if Parent > 0 then
			Visit(Parent);
		end;
		table.insert(Rig.Order, I);
	end;
	for I = 1, #Rig.Parts do
		Visit(I);
	end;

	RigCache[Name] = Rig;
	return Rig;
end;

local RigTau = math.pi * 2;

local function RigWave(Phase, Pow)
	local S = math.sin(RigTau * Phase);
	if Pow > 1 then
		return S > 0 and S ^ Pow or 0; -- only the positive half, sharpened: a swing now and then
	end;
	return S;
end;

-- a kick: swings out, overshoots and settles in about two seconds (1 at its first peak)
local function RigKick(Tau)
	if Tau <= 0 or Tau > 2.6 then
		return 0;
	end;
	return 1.78 * math.exp(-3.2 * Tau) * math.sin(7.54 * Tau);
end;

-- The pose of every part at time T. Mx, My = the pointer (-1..1). Writes a 2x3 matrix per part into Mats (a b c d e f: x' = a x + c y + e,
-- y' = b x + d y + f, in figure units) and how visible it is into Als.
local function RigPose(Rig, T, Mx, My, KickAt, KickS, Mats, Als)
	local Kt = T - KickAt;

	for _, I in ipairs(Rig.Order) do
		local P = Rig.Parts[I];
		local Ang, Ox, Oy, Al = 0, 0, 0, 1;

		for _, A in ipairs(P.Idle) do
			if A.Ch == 's' then
				Ang = Ang + A.Amp * T;
			else
				local Wv = RigWave(T / A.Period + A.Phase, A.Pow);
				if A.Ch == 'r' then
					Ang = Ang + A.Amp * Wv;
				elseif A.Ch == 'x' then
					Ox = Ox + A.Amp * Wv;
				elseif A.Ch == 'y' then
					Oy = Oy + A.Amp * Wv;
				elseif A.Ch == 'a' then
					Al = Al * (1 - A.Amp * (0.5 + 0.5 * Wv));
				end;
			end;
		end;

		local Lk = P.Look;
		if Lk then
			Ang = Ang + Lk.KX * Mx + Lk.KY * My;
			Ox = Ox + Lk.TX * Mx;
			Oy = Oy + Lk.TY * My;
		end;

		local Rc = P.React;
		if Rc and KickS > 0 then
			local K = RigKick(Kt - Rc.Delay) * KickS;
			Ang = Ang + Rc.Amp * K;
			Ox = Ox + Rc.TX * K;
			Oy = Oy + Rc.TY * K;
		end;

		local Rad = math.rad(Ang);
		local C, S = math.cos(Rad), math.sin(Rad);
		local E = P.PX + Ox - (C * P.PX - S * P.PY);
		local F = P.PY + Oy - (S * P.PX + C * P.PY);
		local M = Mats[I];

		if P.Parent > 0 then
			local Q = Mats[P.Parent];
			M[1] = Q[1] * C + Q[3] * S;
			M[2] = Q[2] * C + Q[4] * S;
			M[3] = -Q[1] * S + Q[3] * C;
			M[4] = -Q[2] * S + Q[4] * C;
			M[5] = Q[1] * E + Q[3] * F + Q[5];
			M[6] = Q[2] * E + Q[4] * F + Q[6];
			Als[I] = Al * Als[P.Parent];
		else
			M[1], M[2], M[3], M[4], M[5], M[6] = C, S, -S, C, E, F;
			Als[I] = Al;
		end;
	end;
end;
-- [[/rig:decode]]
-- emblems: the circular line art that turns behind a figure (radius 1; same commands as the figures, plus ticks / star)
--   { 'ticks', n, r1, r2, w, a }   { 'star', n, r, step, w, a, rot, cx, cy }
local function EmPoint(Radius, Deg)
	local Rad = math.rad(Deg);
	return { math.cos(Rad) * Radius, math.sin(Rad) * Radius };
end;

local function EmPoly(N, Radius, Rot)
	local Pts = {};
	for I = 0, N - 1 do
		Pts[#Pts + 1] = EmPoint(Radius, (Rot or -90) + I * 360 / N);
	end;
	return Pts;
end;

local Emblems = {};

Emblems.Void = function() -- a watching rift: almond eye, heptagram, rays
	local C = {
		{ 'ring', 1, 0.022, 1 }, { 'ring', 0.9, 0.008, 0.6 }, { 'ticks', 72, 0.93, 0.99, 0.01, 0.7 }, { 'star', 7, 0.82, 3, 0.01, 0.7, -90, 0, 0 },
		{ 'ell', 0, 0, 0.62, 0.26, 0.022, 1, 0 }, { 'ell', 0, 0, 0.46, 0.19, 0.01, 0.6, 0 }, { 'ring', 0.2, 0.016, 1 }, { 'dot', 0, 0, 0.11, 1 },
		{ 'line', 0, -0.34, 0, 0.34, 0.008, 0.7 },
	};
	for I = 0, 11 do
		local P, Q = EmPoint(0.68, I * 30), EmPoint(0.86, I * 30);
		table.insert(C, { 'line', P[1], P[2], Q[1], Q[2], 0.01, 0.5 });
	end;
	return C;
end;

Emblems.Ocean = function() -- a ship's wheel with a trident in the hub
	local C = { { 'ring', 1, 0.025, 1 }, { 'ring', 0.9, 0.008, 0.55 }, { 'ticks', 48, 0.92, 0.98, 0.01, 0.8 }, { 'ring', 0.34, 0.02, 1 } };
	for I = 0, 7 do
		local A = I * 45;
		local P, Q, S, E = EmPoint(0.98, A), EmPoint(1.14, A), EmPoint(0.34, A), EmPoint(0.98, A);
		table.insert(C, { 'line', P[1], P[2], Q[1], Q[2], 0.04, 0.9 });
		table.insert(C, { 'line', S[1], S[2], E[1], E[2], 0.02, 0.7 });
		table.insert(C, { 'dot', Q[1], Q[2], 0.045, 1 });
	end;
	table.insert(C, { 'line', 0, 0.5, 0, -0.5, 0.045, 1 });
	table.insert(C, { 'poly', { { -0.26, -0.5 }, { -0.26, -0.16 }, { -0.1, 0 }, { 0.1, 0 }, { 0.26, -0.16 }, { 0.26, -0.5 } }, false, 0.032, 1 });
	table.insert(C, { 'poly', { { -0.26, -0.5 }, { -0.31, -0.64 }, { -0.21, -0.58 } }, true, 0.02, 1 });
	table.insert(C, { 'poly', { { 0.26, -0.5 }, { 0.31, -0.64 }, { 0.21, -0.58 } }, true, 0.02, 1 });
	table.insert(C, { 'poly', { { 0, -0.5 }, { -0.06, -0.64 }, { 0, -0.74 }, { 0.06, -0.64 } }, true, 0.02, 1 });
	return C;
end;

Emblems.Sakura = function() -- one blossom: five petals around a core
	local C = { { 'ring', 1, 0.012, 0.6 }, { 'ring', 0.94, 0.006, 0.4 }, { 'ticks', 60, 0.94, 0.99, 0.008, 0.6 } };
	for I = 0, 4 do
		local A = I * 72;
		local P, T, S = EmPoint(0.42, A - 90), EmPoint(0.84, A - 90), EmPoint(0.22, A - 54);
		table.insert(C, { 'blob', P[1], P[2], 0.2, 0.4, 0.28, A });
		table.insert(C, { 'ell', P[1], P[2], 0.2, 0.4, 0.016, 0.95, A });
		table.insert(C, { 'line', P[1], P[2], T[1], T[2], 0.006, 0.4 });
		table.insert(C, { 'line', 0, 0, S[1], S[2], 0.01, 0.8 });
		table.insert(C, { 'dot', S[1], S[2], 0.035, 1 });
	end;
	table.insert(C, { 'dot', 0, 0, 0.07, 1 });
	return C;
end;

Emblems.Galaxy = function() -- a constellation ring
	local C = {
		{ 'ring', 1, 0.016, 1 }, { 'ring', 0.86, 0.006, 0.6 }, { 'ticks', 12, 0.86, 1, 0.03, 0.9 }, { 'ticks', 72, 0.9, 0.96, 0.006, 0.5 },
		{ 'star', 9, 0.8, 4, 0.007, 0.7, -90, 0, 0 }, { 'star', 5, 0.46, 2, 0.01, 0.9, -90, 0, 0 }, { 'ell', 0, 0, 1, 0.32, 0.006, 0.5, 28 }, { 'dot', 0, 0, 0.06, 1 },
	};
	for _, P in ipairs(EmPoly(9, 0.8)) do
		table.insert(C, { 'dot', P[1], P[2], 0.03, 1 });
	end;
	local T, Rot = 1.2, math.rad(28);
	local EX, EY = math.cos(T), 0.32 * math.sin(T);
	table.insert(C, { 'dot', EX * math.cos(Rot) - EY * math.sin(Rot), EX * math.sin(Rot) + EY * math.cos(Rot), 0.07, 1 });
	return C;
end;

Emblems.Heaven = function() -- a sunburst halo with a four point star
	local C = { { 'ring', 1, 0.02, 1 }, { 'ring', 0.78, 0.008, 0.6 }, { 'ring', 0.52, 0.012, 0.8 } };
	for I = 0, 35 do
		local Long = I % 3 == 0;
		local P, Q = EmPoint(0.8, I * 10), EmPoint(Long and 1.14 or 0.96, I * 10);
		table.insert(C, { 'line', P[1], P[2], Q[1], Q[2], Long and 0.024 or 0.01, Long and 1 or 0.6 });
	end;
	table.insert(C, { 'poly', { { 0, -0.46 }, { 0.09, -0.09 }, { 0.46, 0 }, { 0.09, 0.09 }, { 0, 0.46 }, { -0.09, 0.09 }, { -0.46, 0 }, { -0.09, -0.09 } }, true, 0.016, 1 });
	table.insert(C, { 'dot', 0, 0, 0.06, 1 });
	return C;
end;

Emblems.Cyber = function() -- a hex core with circuit lines and a V
	local H1, H2, H3 = EmPoly(6, 1, -90), EmPoly(6, 0.78, -60), EmPoly(6, 0.54, -90);
	local C = { { 'poly', H1, true, 0.02, 1 }, { 'poly', H2, true, 0.01, 0.7 }, { 'poly', H3, true, 0.016, 0.9 } };
	for I, P in ipairs(H1) do
		local Q = H3[I];
		table.insert(C, { 'line', P[1], P[2], Q[1], Q[2], 0.008, 0.6 });
		table.insert(C, { 'dot', P[1], P[2], 0.045, 1 });
	end;
	table.insert(C, { 'poly', { { -0.22, -0.22 }, { 0, 0.2 }, { 0.22, -0.22 } }, false, 0.05, 1 });
	table.insert(C, { 'ring', 0.32, 0.01, 0.7 });
	table.insert(C, { 'ticks', 60, 0.86, 0.92, 0.006, 0.5 });
	table.insert(C, { 'line', -1.1, 0, -0.8, 0, 0.012, 0.7 });
	table.insert(C, { 'line', 1.1, 0, 0.8, 0, 0.012, 0.7 });
	table.insert(C, { 'line', 0, -1.1, 0, -0.8, 0.012, 0.7 });
	table.insert(C, { 'line', 0, 1.1, 0, 0.8, 0.012, 0.7 });
	return C;
end;

Emblems.Inferno = function() -- a ring of flames around a flame
	local C = { { 'ring', 1, 0.02, 1 }, { 'ring', 0.9, 0.008, 0.6 }, { 'ticks', 60, 0.91, 0.99, 0.008, 0.7 }, { 'star', 8, 0.62, 3, 0.008, 0.6, -90, 0, 0 } };
	for I = 0, 7 do
		local A = I * 45 - 90;
		table.insert(C, { 'poly', { EmPoint(0.66, A - 14), EmPoint(0.92, A), EmPoint(0.66, A + 14) }, true, 0.016, 0.9 });
	end;
	table.insert(C, { 'poly', { { 0, -0.52 }, { 0.14, -0.32 }, { 0.28, -0.06 }, { 0.26, 0.18 }, { 0.12, 0.38 }, { 0, 0.44 }, { -0.12, 0.38 }, { -0.26, 0.18 }, { -0.28, -0.06 }, { -0.14, -0.32 } }, true, 0.024, 1 });
	table.insert(C, { 'poly', { { 0, -0.28 }, { 0.1, -0.06 }, { 0.12, 0.14 }, { 0, 0.28 }, { -0.12, 0.14 }, { -0.1, -0.06 } }, true, 0.016, 0.9 });
	table.insert(C, { 'dot', 0, 0.12, 0.06, 1 });
	return C;
end;

Emblems.Vanguard = function() -- a shield with chevrons and a star, blades to both sides
	local C = {
		{ 'poly', EmPoly(6, 1, -90), true, 0.024, 1 }, { 'ring', 0.9, 0.006, 0.5 }, { 'ticks', 48, 0.9, 0.96, 0.008, 0.6 },
		{ 'poly', { { -0.4, -0.46 }, { 0.4, -0.46 }, { 0.4, 0.04 }, { 0, 0.56 }, { -0.4, 0.04 } }, true, 0.034, 1 },
		{ 'poly', { { -0.3, -0.36 }, { 0.3, -0.36 }, { 0.3, 0 }, { 0, 0.42 }, { -0.3, 0 } }, true, 0.012, 0.6 },
		{ 'poly', { { -0.25, -0.16 }, { 0, 0.14 }, { 0.25, -0.16 } }, false, 0.055, 1 }, { 'poly', { { -0.25, 0.02 }, { 0, 0.3 }, { 0.25, 0.02 } }, false, 0.03, 0.7 },
		{ 'star', 5, 0.14, 2, 0.014, 1, -90, 0, -0.74 },
	};
	for _, S in ipairs({ -1, 1 }) do
		table.insert(C, { 'line', S * 0.62, -0.3, S * 1.06, -0.52, 0.03, 0.9 });
		table.insert(C, { 'line', S * 0.62, -0.1, S * 1.12, -0.2, 0.03, 0.8 });
		table.insert(C, { 'line', S * 0.62, 0.1, S * 1.02, 0.08, 0.03, 0.7 });
	end;
	return C;
end;

Emblems.Abyss = function() -- sonar rings, a sweep and a trident
	local C = {
		{ 'ring', 1, 0.016, 1 }, { 'ring', 0.78, 0.01, 0.7 }, { 'ring', 0.56, 0.01, 0.5 }, { 'ring', 0.34, 0.01, 0.4 }, { 'ticks', 72, 0.94, 1, 0.008, 0.6 },
		{ 'line', -1, 0, 1, 0, 0.005, 0.35 }, { 'line', 0, -1, 0, 1, 0.005, 0.35 }, { 'line', 0, 0, 0, -1, 0.05, 0.9 },
		{ 'line', 0, 0.28, 0, -0.3, 0.03, 1 }, { 'poly', { { -0.15, -0.3 }, { -0.15, -0.1 }, { -0.06, 0 }, { 0.06, 0 }, { 0.15, -0.1 }, { 0.15, -0.3 } }, false, 0.022, 1 },
	};
	for _, P in ipairs({ { 0.5, -0.2 }, { -0.3, 0.46 }, { 0.7, 0.3 }, { -0.62, -0.22 } }) do
		table.insert(C, { 'dot', P[1], P[2], 0.03, 0.9 });
	end;
	return C;
end;

Emblems.War = function() -- crossed blades inside a laurel wreath
	local C = { { 'ring', 1, 0.022, 1 }, { 'ring', 0.9, 0.006, 0.5 }, { 'ticks', 24, 0.9, 1, 0.03, 0.9 }, { 'star', 12, 0.98, 5, 0.006, 0.45, -90, 0, 0 } };
	for I = 0, 8 do
		for _, S in ipairs({ -1, 1 }) do
			local A = 90 + S * (22 + I * 12.5);
			local P = EmPoint(0.78, A);
			table.insert(C, { 'blob', P[1], P[2], 0.05, 0.13, 0.6, A + 90 - S * 20 });
		end;
	end;
	for _, S in ipairs({ -1, 1 }) do
		local HX, HY, TX, TY = S * 0.5, 0.6, -S * 0.5, -0.62;
		local DX, DY = TX - HX, TY - HY;
		local Len = math.sqrt(DX * DX + DY * DY);
		local UX, UY = DX / Len, DY / Len;
		local GX, GY = HX + DX * 0.2, HY + DY * 0.2;
		table.insert(C, { 'line', HX, HY, TX, TY, 0.05, 1 });
		table.insert(C, { 'line', GX - UY * 0.2, GY + UX * 0.2, GX + UY * 0.2, GY - UX * 0.2, 0.045, 1 });
		table.insert(C, { 'dot', HX - UX * 0.08, HY - UY * 0.08, 0.05, 1 });
	end;
	return C;
end;

-- the rows of a filled polygon (a menu cannot draw polygons: it fills them with thin rectangles). Rows = rows per unit.
local function ArtScan(Pts, Rows)
	local YMin, YMax = math.huge, -math.huge;
	for _, P in ipairs(Pts) do
		YMin = math.min(YMin, P[2]);
		YMax = math.max(YMax, P[2]);
	end;

	local Out, N, H = {}, #Pts, 1 / Rows;
	local Y = YMin;

	while Y < YMax - 1e-6 do
		local Yc = math.min(Y + H / 2, YMax - 1e-6);
		local Xs = {};

		for I = 1, N do
			local A, B = Pts[I], Pts[I % N + 1];
			if (A[2] <= Yc and B[2] > Yc) or (B[2] <= Yc and A[2] > Yc) then
				table.insert(Xs, A[1] + (Yc - A[2]) * (B[1] - A[1]) / (B[2] - A[2]));
			end;
		end;

		table.sort(Xs);

		for K = 1, #Xs - 1, 2 do
			local X0, X1, Y1 = Xs[K], Xs[K + 1], math.min(Y + H, YMax);
			local Merged = false;

			for _, M in ipairs(Out) do -- a row with the same extent as the one above it just makes that rectangle taller
				if math.abs(M[1] - X0) < 0.006 and math.abs(M[3] - X1) < 0.006 and math.abs(M[4] - Y) < 0.002 then
					M[4] = Y1;
					Merged = true;
					break;
				end;
			end;

			if not Merged then
				table.insert(Out, { X0, Y, X1, Y1 });
			end;
		end;

		Y = Y + H;
	end;

	return Out;
end;

-- Draws a command list. New(Class, Props, Parent) makes an instance; (OX, OY) = where the figure's centre is inside Parent (px),
-- Unit = pixels per figure unit, Pal = four Color3 (a single colour is used for all), Fade = factor on every opacity (1 = as written).
local function DrawArt(New, Parent, Cmds, OX, OY, Unit, Pal, Fade)
	Fade = Fade or 1;
	local Slot = 1;
	local Rows = math.clamp(math.floor(Unit / 3.5), 8, 60);

	local function Col()
		return Pal[Slot] or Pal[1];
	end;

	local function Tr(A)
		return 1 - math.clamp((A or 1) * Fade, 0, 1);
	end;

	local function Center(X, Y)
		return UDim2.fromOffset(OX + X * Unit, OY + Y * Unit);
	end;

	local function Thick(W)
		return math.max(1, W * Unit);
	end;

	local function Line(X1, Y1, X2, Y2, W, A)
		local DX, DY = (X2 - X1) * Unit, (Y2 - Y1) * Unit;
		local Len = math.sqrt(DX * DX + DY * DY);
		if Len < 0.5 then
			return;
		end;

		local F = New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Col(); BackgroundTransparency = Tr(A);
			Position = Center((X1 + X2) / 2, (Y1 + Y2) / 2); Rotation = math.deg(math.atan2(DY, DX));
			Size = UDim2.fromOffset(Len + Thick(W) * 0.5, Thick(W));
		}, Parent);
		Round(F, 0.5, 0);
	end;

	local function Disc(Rx, Ry, Cx, Cy, Rot, Filled, W, A)
		local F = New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Col(); BackgroundTransparency = Filled and Tr(A) or 1;
			Position = Center(Cx, Cy); Rotation = Rot or 0;
			Size = UDim2.fromOffset(math.max(2, Rx * 2 * Unit), math.max(2, Ry * 2 * Unit));
		}, Parent);
		Round(F, 0.5, 0);

		if not Filled then
			local Stroke = Instance.new('UIStroke');
			Stroke.Color = Col();
			Stroke.Thickness = Thick(W);
			Stroke.Transparency = Tr(A);
			Stroke.Parent = F;
		end;
	end;

	for _, C in ipairs(Cmds) do
		local K = C[1];

		if K == 'c' then
			Slot = C[2];
		elseif K == 'ring' then
			Disc(C[2], C[2], 0, 0, 0, false, C[3], C[4]);
		elseif K == 'dot' then
			Disc(C[4], C[4], C[2], C[3], 0, true, 0, C[5]);
		elseif K == 'ell' then
			Disc(C[4], C[5], C[2], C[3], C[8], false, C[6], C[7]);
		elseif K == 'blob' then
			Disc(C[4], C[5], C[2], C[3], C[7], true, 0, C[6]);
		elseif K == 'line' then
			Line(C[2], C[3], C[4], C[5], C[6], C[7]);
		elseif K == 'poly' then
			local P = C[2];
			for I = 1, #P - 1 do
				Line(P[I][1], P[I][2], P[I + 1][1], P[I + 1][2], C[4], C[5]);
			end;
			if C[3] and #P > 2 then
				Line(P[#P][1], P[#P][2], P[1][1], P[1][2], C[4], C[5]);
			end;
		elseif K == 'fill' then
			for _, R in ipairs(ArtScan(C[2], Rows)) do
				New('Frame', {
					BackgroundColor3 = Col(); BackgroundTransparency = Tr(C[3]);
					Position = Center(R[1], R[2]);
					Size = UDim2.fromOffset(math.ceil((R[3] - R[1]) * Unit) + 1, math.ceil((R[4] - R[2]) * Unit) + 1);
				}, Parent);
			end;
		elseif K == 'star' then
			local N = C[2];
			local V = EmPoly(N, C[3], C[7]);
			local SX, SY = C[8] or 0, C[9] or 0;
			for I = 1, N do
				local P1, P2 = V[I], V[(I - 1 + C[4]) % N + 1];
				Line(P1[1] + SX, P1[2] + SY, P2[1] + SX, P2[2] + SY, C[5], C[6]);
			end;
		elseif K == 'ticks' then
			-- every frame crosses the centre and only shows its two ends (the middle fades out), so one frame draws two ticks
			local N = math.max(math.floor(C[2] / 2), 1);
			local R1, R2 = C[3], C[4];
			local Cut = math.clamp((R2 - R1) / (2 * R2), 0.01, 0.45);

			for I = 0, N - 1 do
				local F = New('Frame', {
					AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Col(); BackgroundTransparency = Tr(C[6]);
					Position = Center(0, 0); Rotation = I * (360 / C[2]) - 90;
					Size = UDim2.fromOffset(2 * R2 * Unit, Thick(C[5]));
				}, Parent);
				New('UIGradient', {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(Cut, 0), NumberSequenceKeypoint.new(Cut + 0.001, 1),
						NumberSequenceKeypoint.new(1 - Cut - 0.001, 1), NumberSequenceKeypoint.new(1 - Cut, 0), NumberSequenceKeypoint.new(1, 0),
					});
				}, F);
			end;
		end;
	end;
end;

-- a CanvasGroup (a Frame when the engine has none) that is not clipped by anything else, drawn once
local function MakeCanvas(R, Props, Parent)
	Props.BackgroundTransparency = 1;
	local C = Library:CreateCanvas(Props);
	C.BorderSizePixel = 0;
	C.ZIndex = R.Z;
	C.Parent = Parent;
	return C;
end;

local function IsGroup(C)
	return C:IsA('CanvasGroup');
end;

-- [[rig:hero]]
-- Little effects that leave a part of a figure when it is kicked (a tab change, a pressed control). Layer = the renderer layer the tweens
-- belong to, Parent = a frame over the figure whose middle is the figure's centre (Cx, Cy px), Unit = px per figure unit.
-- Spec: Kind (ring spark streak slash bubble petal), X / Y (figure units), Slot (colour 1..4), N (how many), Power (1 = a tab change)
function RM:Burst(Parent, Pal, Spec)
	local Layer = Spec.Layer or 'Atmosphere';
	local U, Power = Spec.Unit, Spec.Power;
	local Col = Pal[Spec.Slot] or Pal[1];
	local Count = math.max(1, math.floor(Spec.N * Power + 0.5));
	local PX, PY = Spec.Cx + Spec.X * U, Spec.Cy + Spec.Y * U;
	local Kind = Spec.Kind;

	local function Done(Tween, Inst)
		Tween.Completed:Once(function()
			Inst:Destroy();
		end);
	end;

	local function Piece(Props)
		Props.AnchorPoint = Vector2.new(0.5, 0.5);
		Props.BorderSizePixel = 0;
		return self:New('Frame', Props, Parent);
	end;

	if Kind == 'ring' then
		local R0 = 0.1 * U;
		local F = Piece({ BackgroundTransparency = 1; Position = UDim2.fromOffset(PX, PY); Size = UDim2.fromOffset(R0 * 0.6, R0 * 0.6); });
		Round(F, 0.5, 0);

		local Stroke = Instance.new('UIStroke');
		Stroke.Color = Col;
		Stroke.Thickness = math.max(1.5, U * 0.012);
		Stroke.Transparency = 0.05;
		Stroke.Parent = F;

		local Big = R0 * 2 * (1 + 3.4 * Power);
		Done(self:Tween(F, { Size = UDim2.fromOffset(Big, Big) }, 0.8, Enum.EasingStyle.Quint, EOut, Layer), F);
		self:Tween(Stroke, { Transparency = 1 }, 0.8, Linear, EOut, Layer);
	elseif Kind == 'spark' then
		for _ = 1, Count do
			local S = math.max(2, U * Roll({ 0.014, 0.026 }));
			local A, Dist = Roll({ 0, RigTau }), U * Roll({ 0.22, 0.7 }) * Power;
			local F = Piece({ BackgroundColor3 = Col; Position = UDim2.fromOffset(PX, PY); Size = UDim2.fromOffset(S, S); });
			Round(F, 0.5, 0);

			Done(self:Tween(F, {
				Position = UDim2.fromOffset(PX + math.cos(A) * Dist, PY + math.sin(A) * Dist + U * 0.12);
				Size = UDim2.fromOffset(S * 0.2, S * 0.2); BackgroundTransparency = 1;
			}, Roll({ 0.55, 0.95 }), Enum.EasingStyle.Quad, EOut, Layer), F);
		end;
	elseif Kind == 'streak' then
		for _ = 1, Count do
			local A, Len = Roll({ 0, RigTau }), U * Roll({ 0.1, 0.2 });
			local D0, D1 = U * 0.05, U * Roll({ 0.3, 0.75 }) * Power;
			local F = Piece({
				BackgroundColor3 = Col; Position = UDim2.fromOffset(PX + math.cos(A) * D0, PY + math.sin(A) * D0);
				Rotation = math.deg(A); Size = UDim2.fromOffset(Len, 2);
			});
			Round(F, 0.5, 0);

			Done(self:Tween(F, {
				Position = UDim2.fromOffset(PX + math.cos(A) * D1, PY + math.sin(A) * D1); Size = UDim2.fromOffset(Len * 0.4, 2); BackgroundTransparency = 1;
			}, Roll({ 0.38, 0.64 }), Enum.EasingStyle.Quad, EOut, Layer), F);
		end;
	elseif Kind == 'slash' then
		local Len = U * 0.95;
		local Ang = Roll({ 18, 38 }) * (FXRandom:NextNumber() < 0.5 and 1 or -1);
		local F = Piece({ BackgroundColor3 = Col; Position = UDim2.fromOffset(PX, PY); Rotation = -Ang; Size = UDim2.fromOffset(Len * 0.1, 4); });
		Round(F, 0.5, 0);
		self:New('UIGradient', { Transparency = NS(0, 1, 0.4, 0, 0.6, 0, 1, 1); }, F);

		local Grow = self:Tween(F, { Size = UDim2.fromOffset(Len * 1.1, 4) }, 0.5, Enum.EasingStyle.Quint, EOut, Layer);
		Done(Grow, F);
		self:Tween(F, { BackgroundTransparency = 0.9 }, 0.5, Linear, EOut, Layer, 0, false, 0.15);
	elseif Kind == 'bubble' then
		for _ = 1, Count do
			local S = U * Roll({ 0.03, 0.08 });
			local X0, Dx = PX + Roll({ -0.06, 0.06 }) * U, Roll({ -0.12, 0.12 }) * U;
			local F = Piece({ BackgroundTransparency = 1; Position = UDim2.fromOffset(X0, PY); Size = UDim2.fromOffset(S, S); });
			Round(F, 0.5, 0);

			local Stroke = Instance.new('UIStroke');
			Stroke.Color = Col;
			Stroke.Thickness = 1.5;
			Stroke.Transparency = 0.1;
			Stroke.Parent = F;

			local Time = Roll({ 1.1, 1.8 });
			Done(self:Tween(F, { Position = UDim2.fromOffset(X0 + Dx, PY - U * 0.75 * Power) }, Time, Enum.EasingStyle.Quad, EOut, Layer), F);
			self:Tween(Stroke, { Transparency = 1 }, Time, Linear, EOut, Layer);
		end;
	elseif Kind == 'petal' then
		for _ = 1, Count do
			local W = U * Roll({ 0.025, 0.045 });
			local A, Dist = Roll({ -2.6, -0.5 }), U * Roll({ 0.25, 0.6 }) * Power;
			local F = Piece({ BackgroundColor3 = Col; Position = UDim2.fromOffset(PX, PY); Size = UDim2.fromOffset(W, W * 1.7); });
			Round(F, 0.5, 0);

			Done(self:Tween(F, {
				Position = UDim2.fromOffset(PX + math.cos(A) * Dist * 1.2, PY + math.sin(A) * Dist * 0.4 + U * 0.55);
				Rotation = Roll({ -160, 160 }); BackgroundTransparency = 1;
			}, Roll({ 1.2, 2 }), Enum.EasingStyle.Sine, EInOut, Layer), F);
		end;
	end;
end;

-- The hero of a scene: a rigged figure behind the menu that stays where it is. Its joints move on their own (it breathes, wings flutter,
-- tentacles ripple), it looks toward the mouse a little, and when the tab changes (or a control is pressed) it does a short move with a few
-- sparks (FX:ReactSigils / FX:PokeAt).
-- Spec: Fig (a name from Figures), Pal (4 colours), Size (fraction of the window's smaller side), Alpha (opacity of the figure),
--       At { x, y } (window fractions: where it stands), Layer
function RM:Hero(Spec)
	local Cmds = DecodeFigure(Spec.Fig);
	if not Cmds then
		return;
	end;

	local Rig = DecodeRig(Spec.Fig);
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Win = self:Size();
	local Px = math.floor((Spec.Size or 1) * math.min(Win.X, Win.Y));
	local At = Spec.At or { 0.6, 0.5 };
	local Alpha = Spec.Alpha or 0.8;
	local Unit = Px / 2.2;
	local Pal = Spec.Pal;

	local function New(Class, Props, Parent)
		return self:New(Class, Props, Parent);
	end;

	local Mover = self:New('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Position = UDim2.fromScale(At[1], At[2]); Size = UDim2.fromOffset(Px, Px);
	}, Layer);

	local Scale = Instance.new('UIScale');
	Scale.Parent = Mover;

	-- a bit of room around the figure: parts swing, drift and turn outside of it
	local Side = math.floor(Px * 1.32);
	local C = Side / 2;

	local Figure = MakeCanvas(self, { AnchorPoint = Vector2.new(0.5, 0.5); Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromOffset(Side, Side); }, Mover);
	local Grouped = IsGroup(Figure);
	if Grouped then
		Figure.GroupTransparency = 1 - Alpha;
	end;

	local Hero = { Mover = Mover; Scale = Scale; Alpha = Alpha; Base = 1; KickAt = -99; KickS = 0; Figure = Figure; Grouped = Grouped; Rig = Rig; };

	if Rig then
		-- cut the commands into parts (each starts with the colour that was set before it)
		local Lists, Slot, Cur = {}, 1, nil;
		for _, Cm in ipairs(Cmds) do
			if Cm[1] == 'g' then
				Cur = { { 'c', Slot } };
				Lists[Cm[2]] = Cur;
			else
				if Cm[1] == 'c' then
					Slot = Cm[2];
				end;
				if Cur then
					table.insert(Cur, Cm);
				end;
			end;
		end;

		-- one canvas per part, in drawing order, sized to its box and anchored at its pivot: moving / turning it is a Position / Rotation
		local Canvases, Seen, Mats, Als = {}, {}, {}, {};
		for I, Part in ipairs(Rig.Parts) do
			Mats[I] = { 1, 0, 0, 1, 0, 0 };
			Als[I] = 1;
			Seen[I] = {};

			local List, B = Lists[Part.Id], Part.Box;
			if List and #List > 1 and B[3] > B[1] and B[4] > B[2] then
				local W, H = math.ceil((B[3] - B[1]) * Unit) + 2, math.ceil((B[4] - B[2]) * Unit) + 2;
				local Canvas = MakeCanvas(self, {
					AnchorPoint = Vector2.new((Part.PX - B[1]) / (B[3] - B[1]), (Part.PY - B[2]) / (B[4] - B[2]));
					Position = UDim2.fromOffset(C + Part.PX * Unit, C + Part.PY * Unit); Size = UDim2.fromOffset(W, H);
				}, Figure);

				DrawArt(New, Canvas, List, -B[1] * Unit + 1, -B[2] * Unit + 1, Unit, Pal, Grouped and 1 or Alpha);
				Canvases[I] = Canvas;

				for _, A in ipairs(Part.Idle) do
					if A.Ch == 'a' then
						Part.Fades = true;
					end;
				end;
			end;
		end;

		local FxFrame = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromOffset(Side, Side);
		}, Mover);

		-- a kick: Power 1 = a tab change, less = a pressed control. A weaker kick right after a stronger one is ignored
		function Hero.React(Power, IsTab)
			if self.Time - Hero.KickAt < 0.35 and Hero.KickS >= Power then
				return;
			end;
			Hero.KickAt, Hero.KickS = self.Time, Power;

			if not (self.E and self.E.Particles) then
				return;
			end;

			for _, E in ipairs(Rig.Fx) do
				if IsTab or E.Level == 0 then
					local M = Mats[E.Part];
					self:Burst(FxFrame, Pal, {
						Kind = E.Kind; Slot = E.Slot; N = E.N; Power = Power; Unit = Unit; Cx = C; Cy = C; Layer = LayerName;
						X = M[1] * E.X + M[3] * E.Y + M[5]; Y = M[2] * E.X + M[4] * E.Y + M[6];
					});
				end;
			end;
		end;

		local Mx, My = 0, 0;
		self:Tick(function(T, Dt)
			local Tx, Ty = 0, 0;
			if InputService.MouseEnabled then
				local P, S = Layer.AbsolutePosition, Layer.AbsoluteSize;
				if S.X > 10 and S.Y > 10 then
					Tx = math.clamp((Mouse.X - (P.X + S.X * At[1])) / (S.X * 0.5), -1, 1);
					Ty = math.clamp((Mouse.Y - (P.Y + S.Y * At[2])) / (S.Y * 0.5), -1, 1);
				end;
			end;

			local Ease = 1 - math.exp(-Dt * 4.5); -- the figure turns toward the pointer smoothly
			Mx = Mx + (Tx - Mx) * Ease;
			My = My + (Ty - My) * Ease;

			RigPose(Rig, T, Mx, My, Hero.KickAt, Hero.KickS, Mats, Als);

			for I, Part in ipairs(Rig.Parts) do
				local Canvas = Canvases[I];
				if Canvas then
					local M, Last = Mats[I], Seen[I];
					local X = C + (M[1] * Part.PX + M[3] * Part.PY + M[5]) * Unit; -- where its pivot is now
					local Y = C + (M[2] * Part.PX + M[4] * Part.PY + M[6]) * Unit;
					local Turn = math.deg(math.atan2(M[2], M[1]));

					if not Last.X or math.abs(X - Last.X) > 0.12 or math.abs(Y - Last.Y) > 0.12 then
						Last.X, Last.Y = X, Y;
						Canvas.Position = UDim2.fromOffset(X, Y);
					end;

					if not Last.R or math.abs(Turn - Last.R) > 0.02 then
						Last.R = Turn;
						Canvas.Rotation = Turn;
					end;

					if Part.Fades and Grouped then
						local G = 1 - Als[I];
						if not Last.G or math.abs(G - Last.G) > 0.01 then
							Last.G = G;
							Canvas.GroupTransparency = G;
						end;
					end;
				end;
			end;
		end, LayerName);
	else
		-- a plain figure (no rig): drawn once, floats a little
		DrawArt(New, Figure, Cmds, C, C, Unit, Pal, Grouped and 1 or Alpha);
		self:Sway(Figure, { Position = { UDim2.fromScale(0.5, 0.5), UDim2.new(0.5, 0, 0.5, -Px * 0.014) } }, Roll({ 2, 2.8 }), LayerName);
	end;

	self.Sigils = self.Sigils or {};
	table.insert(self.Sigils, Hero);
end;

-- the tab changed: every hero does its move, pops a little and flashes
function RM:HeroReact()
	if not (self.Sigils and self.E and self.E.Animated and self:Shown()) then
		return;
	end;

	for _, H in ipairs(self.Sigils) do
		if H.Mover.Parent then
			if H.React then
				H.React(1, true);
			end;

			local Up = Tw(H.Scale, { Scale = H.Base * 1.04 }, 0.25, Enum.EasingStyle.Quad);
			Up.Completed:Once(function(State)
				if State == Enum.PlaybackState.Completed and H.Scale.Parent then
					Tw(H.Scale, { Scale = H.Base }, 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out);
				end;
			end);

			if H.Grouped then
				local Lit = Tw(H.Figure, { GroupTransparency = math.max(1 - H.Alpha * 1.3, 0) }, 0.15, Enum.EasingStyle.Quad);
				Lit.Completed:Once(function(State)
					if State == Enum.PlaybackState.Completed and H.Figure.Parent then
						Tw(H.Figure, { GroupTransparency = 1 - H.Alpha }, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
					end;
				end);
			end;
		end;
	end;
end;

-- a control was pressed: a smaller version of the same move
function RM:HeroPoke()
	if not (self.Sigils and self.E and self.E.Animated and self:Shown()) then
		return;
	end;

	for _, H in ipairs(self.Sigils) do
		if H.Mover.Parent and H.React then
			H.React(0.5, false);
		end;
	end;
end;

-- called when the tab changes (Tab:ShowTab): every hero on screen reacts, and so does whatever hangs from the window
function FX:ReactSigils(Index)
	if not FX.Settings.Animations then
		return;
	end;

	for R in next, FX.Renderers do
		if R.Sigils and #R.Sigils > 0 then
			R:HeroReact(Index);
		end;
	end;

	if FX.AccessoryKick then
		FX.AccessoryKick(1);
	end;
end;

-- a press at (X, Y): the hero of the window under it reacts a little
local LastPoke = 0;

function FX:PokeAt(X, Y)
	if not FX.Settings.Animations then
		return;
	end;

	local Now = os.clock();
	if Now - LastPoke < 0.26 then
		return;
	end;

	for R in next, FX.Renderers do
		if R.Sigils and #R.Sigils > 0 and R:Shown() then
			local P, S = R.Holder.AbsolutePosition, R.Holder.AbsoluteSize;
			if X >= P.X and Y >= P.Y and X <= P.X + S.X and Y <= P.Y + S.Y then
				LastPoke = Now;
				R:HeroPoke();

				if FX.AccessoryKick then
					FX.AccessoryKick(0.5);
				end;
			end;
		end;
	end;
end;

Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
	if IsPress(Input) then
		local X, Y = Library:GetPointer(Input);
		FX:PokeAt(X, Y);
	end;
end));
-- [[/rig:hero]]

-- Soft ribbons of light hanging from the top (northern lights).
-- Spec: Layer, Count, Colors, Width {min, max} px, X {min, max}, Top, Height (window heights), Alpha (transparency at the brightest point)
function RM:Curtain(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Size = self:Size();

	for I = 1, (Spec.Count or 3) do
		local W = Roll(Spec.Width or { 90, 160 });
		local H = Size.Y * (Spec.Height or 0.8);

		local F = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0); BackgroundColor3 = Spec.Colors[(I - 1) % #Spec.Colors + 1];
			Position = UDim2.new(Roll(Spec.X or { 0.1, 0.9 }), 0, Spec.Top or 0, 0); Size = UDim2.fromOffset(W, H);
		}, Layer);
		self:New('UIGradient', { Rotation = 90; Transparency = NS(0, 1, 0.38, Spec.Alpha or 0.85, 1, 1); }, F);
		self:Sway(F, { Rotation = { -9, 9 }; Size = { UDim2.fromOffset(W * 0.8, H), UDim2.fromOffset(W * 1.25, H) }; }, Roll({ 3.5, 6 }), LayerName);
	end;
end;

-- Bolts of lightning at random: a jagged line (a soft thick one under a thin white one) and a flash over the scene. Scripted: the
-- gap between two bolts is random.
-- Spec: Layer, Color, Period {min, max} seconds, Reach (how far down a bolt goes, window heights), Flash (opacity of the flash)
function RM:Lightning(Spec)
	local LayerName = Spec.Layer or 'Lighting';
	local Layer = self.Layers[LayerName];
	local Color = Spec.Color or Color3.new(1, 1, 1);
	local Period = Spec.Period or { 5, 9 };

	local Flash = self:New('Frame', { BackgroundColor3 = Color; BackgroundTransparency = 1; Size = UDim2.fromScale(1, 1); }, Layer);
	local NextAt = Roll(Period) * 0.5;

	self:Tick(function(T)
		if T < NextAt then
			return;
		end;
		NextAt = T + Roll(Period);

		local Win = self:Size();
		local X, Y = Roll({ 0.1, 0.9 }) * Win.X, -10;
		local Steps = FXRandom:NextInteger(7, 11);
		local Step = (Spec.Reach or 0.7) * Win.Y / Steps;

		local Bolt = self:New('Frame', { BackgroundTransparency = 1; Size = UDim2.fromScale(1, 1); }, Layer);

		for _ = 1, Steps do
			local NX, NY = X + Roll({ -46, 46 }), Y + Step * Roll({ 0.7, 1.2 });
			local DX, DY = NX - X, NY - Y;
			local Len = math.sqrt(DX * DX + DY * DY);

			for _, Pass in ipairs({ { 7, 0.75, Color }, { 2.2, 0, Color3.new(1, 1, 1) } }) do
				self:New('Frame', {
					AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Pass[3]; BackgroundTransparency = Pass[2];
					Position = UDim2.fromOffset((X + NX) / 2, (Y + NY) / 2); Rotation = math.deg(math.atan2(DY, DX));
					Size = UDim2.fromOffset(Len + 2, Pass[1]);
				}, Bolt);
			end;

			X, Y = NX, NY;
		end;

		Flash.BackgroundTransparency = 1 - (Spec.Flash or 0.25);
		Tw(Flash, { BackgroundTransparency = 1 }, 0.5, Enum.EasingStyle.Quad);

		for _, Segment in ipairs(Bolt:GetChildren()) do
			Tw(Segment, { BackgroundTransparency = 1 }, 0.5, Enum.EasingStyle.Quad);
		end;

		task.delay(0.6 * Library.AnimationSpeed + 0.1, function()
			Bolt:Destroy();
		end);
	end, LayerName);
end;

-- Caustic light patches wobbling near the surface. Spec: Layer, Count, Depth (window heights), Color, Alpha (transparency of one patch)
function RM:Caustics(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local E = self.E or self:Get();
	local Count = math.max(math.floor((Spec.Count or 12) * math.clamp(E.Profile.Scale, 0.5, 1) + 0.5), 1);

	for _ = 1, Count do
		local W = Roll({ 70, 190 });
		local H = W * Roll({ 0.3, 0.5 });

		local F = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Color or Color3.new(1, 1, 1); BackgroundTransparency = Spec.Alpha or 0.9;
			Position = UDim2.fromScale(Roll({ 0, 1 }), Roll({ 0, Spec.Depth or 0.5 })); Size = UDim2.fromOffset(W, H);
		}, Layer);
		Round(F, 0.5, 0);

		self:Sway(F, { Size = { UDim2.fromOffset(W * 0.8, H * 1.2), UDim2.fromOffset(W * 1.25, H * 0.8) }; BackgroundTransparency = { (Spec.Alpha or 0.9) - 0.04, (Spec.Alpha or 0.9) + 0.05 }; }, Roll({ 2, 4 }), LayerName);
	end;
end;

-- A whale (head to the left) that crosses the picture very slowly. Spec: Layer, Y (window heights), Size (px long), Color, Alpha, Seconds
function RM:Whale(Spec)
	local LayerName = Spec.Layer or 'Decor';
	local Layer = self.Layers[LayerName];
	local Win = self:Size();
	local W = Spec.Size or Win.X * 0.5;
	local H = W * 0.3;

	local Body = self:New('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; Position = UDim2.fromScale(1.3, Spec.Y or 0.5); Size = UDim2.fromOffset(W, H);
	}, Layer);

	local Alpha = Spec.Alpha or 0.6;
	local Hull = self:New('Frame', {
		AnchorPoint = Vector2.new(0, 0.5); BackgroundColor3 = Spec.Color; BackgroundTransparency = Alpha;
		Position = UDim2.fromScale(0, 0.5); Size = UDim2.fromScale(0.8, 1);
	}, Body);
	Round(Hull, 0.5, 0);

	for _, Tilt in ipairs({ 24, -24 }) do -- the two lobes of the tail fluke
		local Lobe = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Color; BackgroundTransparency = Alpha;
			Position = UDim2.fromScale(0.9, 0.5); Rotation = Tilt; Size = UDim2.fromScale(0.22, 0.2);
		}, Body);
		Round(Lobe, 0.5, 0);
	end;

	self:Cycle(Body, { Position = { UDim2.fromScale(1.3, Spec.Y or 0.5), UDim2.fromScale(-0.3, Spec.Y or 0.5) } }, Spec.Seconds or 80, LayerName);
end;

-- A searchlight sweeping from a point on the bottom edge. Spec: Layer, X (window width), Color, Alpha (transparency at the lamp),
-- Sweep { from, to } degrees, Seconds (one swing)
function RM:Beam(Spec)
	local LayerName = Spec.Layer or 'Atmosphere';
	local Layer = self.Layers[LayerName];
	local Win = self:Size();

	local Pivot = self:New('Frame', { BackgroundTransparency = 1; Position = UDim2.new(Spec.X or 0.1, 0, 1, 0); Size = UDim2.fromOffset(0, 0); }, Layer);

	for _, Wide in ipairs({ 150, 70 }) do
		local Beam = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 1); BackgroundColor3 = Spec.Color; Position = UDim2.fromOffset(0, 0);
			Size = UDim2.fromOffset(Wide, Win.Y * 1.15);
		}, Pivot);
		self:New('UIGradient', { Rotation = 90; Transparency = NS(0, 1, 1, Spec.Alpha or 0.7); }, Beam);
	end;

	local Sweep = Spec.Sweep or { -20, 20 };
	self:Sway(Pivot, { Rotation = Sweep }, Spec.Seconds or 7, LayerName);
end;

-- A ruined column floating in the air. Spec: Layer, X, Y (window fractions), Width, Height (px), Rotation, Alpha (transparency)
function RM:Pillar(Spec)
	local LayerName = Spec.Layer or 'Decor';
	local Layer = self.Layers[LayerName];
	local W, H = Spec.Width or 36, Spec.Height or 130;
	local Alpha = Spec.Alpha or 0.45;

	local Root = self:New('Frame', {
		AnchorPoint = Vector2.new(0.5, 0); BackgroundTransparency = 1; Position = UDim2.fromScale(Spec.X, Spec.Y);
		Rotation = Spec.Rotation or 0; Size = UDim2.fromOffset(W, H);
	}, Layer);

	local Shaft = self:New('Frame', { BackgroundColor3 = Color3.new(1, 1, 1); BackgroundTransparency = Alpha; Size = UDim2.fromScale(1, 1); }, Root);
	self:New('UIGradient', { Color = Seq(RGB(40, 24, 40), RGB(168, 126, 90), RGB(40, 24, 40)); }, Shaft);

	for _, Part in ipairs({ { -6, -5 }, { -6, H - 3 } }) do -- capital and base
		self:New('Frame', { BackgroundColor3 = RGB(214, 172, 112); BackgroundTransparency = Alpha; Position = UDim2.fromOffset(Part[1], Part[2]); Size = UDim2.fromOffset(W + 12, 8); }, Root);
	end;

	for I = 1, 4 do -- fluting
		self:New('Frame', { BackgroundColor3 = RGB(255, 222, 150); BackgroundTransparency = 0.78; Position = UDim2.fromOffset(4, H * I / 5); Size = UDim2.fromOffset(W - 8, 1); }, Root);
	end;

	local Rot = Spec.Rotation or 0;
	self:Sway(Root, { Rotation = { Rot, Rot + 3 }; Position = { UDim2.fromScale(Spec.X, Spec.Y), UDim2.new(Spec.X, 0, Spec.Y, -12) }; }, Roll({ 4, 6 }), LayerName);
end;

-- Fiery (or icy) streaks that cross the picture now and then. Scripted: random gaps. Spec: Layer, Count, Color, Angle (degrees below horizontal)
function RM:Meteors(Spec)
	local LayerName = Spec.Layer or 'Lighting';
	local Layer = self.Layers[LayerName];
	local E = self.E or self:Get();
	if E.Profile.Cap <= 0 then
		return;
	end;

	local Angle = Spec.Angle or 30;
	local DX, DY = math.cos(math.rad(Angle)) * 0.6, math.sin(math.rad(Angle)) * 0.6;

	for I = 1, (Spec.Count or 3) do
		local Streak = self:New('Frame', {
			AnchorPoint = Vector2.new(1, 0.5); BackgroundColor3 = Spec.Color or Color3.new(1, 1, 1); Rotation = Angle;
			Size = UDim2.fromOffset(Roll({ 90, 170 }), 3); Visible = false;
		}, Layer);
		Round(Streak, 0.5, 0);
		self:New('UIGradient', { Transparency = NS(0, 1, 0.8, 0.3, 1, 0); }, Streak);

		local NextAt = I + FXRandom:NextNumber() * 4;

		self:Tick(function(T)
			if T < NextAt then
				return;
			end;
			NextAt = T + 4 + FXRandom:NextNumber() * 6;

			local SX, SY = -0.1 + FXRandom:NextNumber() * 0.8, -0.05 + FXRandom:NextNumber() * 0.4;
			Streak.Position = UDim2.fromScale(SX, SY);
			Streak.BackgroundTransparency = 0.1;
			Streak.Visible = true;

			local Tween = Tw(Streak, { Position = UDim2.fromScale(SX + DX, SY + DY); BackgroundTransparency = 1; }, 0.9, Enum.EasingStyle.Quad);
			Tween.Completed:Once(function()
				Streak.Visible = false;
			end);
		end, LayerName);
	end;
end;

-- A jellyfish: a glowing bell with trailing tentacles, bobbing up and down. Spec: Layer, Position (UDim2), Size (px), Color
function RM:Jelly(Spec)
	local LayerName = Spec.Layer or 'Decor';
	local Layer = Spec.Parent or self.Layers[LayerName];
	local Size = Spec.Size or 60;
	local Color = Spec.Color or Color3.new(1, 1, 1);
	local Pos = Spec.Position or UDim2.fromScale(0.5, 0.5);

	local Root = self:New('Frame', { BackgroundTransparency = 1; Position = Pos; Size = UDim2.fromOffset(0, 0); }, Layer);

	local Halo = self:New('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color; BackgroundTransparency = 0.86;
		Position = UDim2.fromOffset(0, 0); Size = UDim2.fromOffset(Size * 1.7, Size * 1.2);
	}, Root);
	Round(Halo, 0.5, 0);

	local Bell = self:New('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color3.new(1, 1, 1); BackgroundTransparency = 0.12;
		Position = UDim2.fromOffset(0, 0); Size = UDim2.fromOffset(Size, Size * 0.62);
	}, Root);
	Round(Bell, 0.5, 0);
	self:New('UIGradient', { Rotation = 90; Color = Seq(RGB(255, 255, 255), Color); }, Bell);

	for I = 1, 6 do
		local Pivot = self:New('Frame', { BackgroundTransparency = 1; Position = UDim2.fromOffset((I - 3.5) * Size * 0.16, Size * 0.26); Size = UDim2.fromOffset(0, 0); }, Root);
		local Tentacle = self:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0); BackgroundColor3 = Color; Size = UDim2.fromOffset(2, Size * (0.7 + (I % 3) * 0.22));
		}, Pivot);
		self:New('UIGradient', { Rotation = 90; Transparency = NS(0, 0.2, 1, 1); }, Tentacle);
		self:Sway(Pivot, { Rotation = { -12, 12 } }, Roll({ 1.2, 2.2 }), LayerName);
	end;

	-- it swims the way jellyfish do: the bell squeezes and pushes it up quickly, then it sinks slowly while it drifts sideways on a long path;
	-- every one has its own rhythm. The path is scripted (a tick), the tentacles sway on their own (tweens)
	local Phase, Speed, Phase2 = FXRandom:NextNumber(), Roll({ 0.16, 0.23 }), FXRandom:NextNumber() * 2 * math.pi;
	local W1, W2 = Roll({ 0.07, 0.11 }) * 2 * math.pi, Roll({ 0.05, 0.09 }) * 2 * math.pi;
	local AX, AY, Bob = Size * Roll({ 0.5, 1 }), Size * 0.25, Size * 0.55;

	self:Tick(function(T)
		local P = (T * Speed + Phase) % 1;
		local Up, Squeeze = 0, 0;

		if P < 0.3 then
			local K = P / 0.3;
			Up = K * K * (3 - 2 * K);
			Squeeze = math.sin(K * math.pi);
		else
			local K = (P - 0.3) / 0.7;
			Up = 1 - K * K * (3 - 2 * K);
		end;

		Root.Position = Pos + UDim2.fromOffset(AX * math.sin(T * W1 + Phase2), AY * math.sin(T * W2) - Bob * Up);
		Bell.Size = UDim2.fromOffset(Size * (1 - 0.15 * Squeeze), Size * 0.62 * (1 + 0.1 * Squeeze));
	end, LayerName);

	self:Sway(Halo, { BackgroundTransparency = { 0.8, 0.92 } }, Roll({ 0.9, 1.6 }), LayerName);
end;


-- ---------------------------------------------------------------- decoration builders (frames only, no assets)

local function BuildAnchor(Parent, Size, Color, Z, Alpha)
	local C = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; BorderSizePixel = 0;
		Size = UDim2.fromOffset(Size, Size); ZIndex = Z; Parent = Parent;
	});

	local function Pill(X, Y, W, H, Rotation)
		local P = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color; BackgroundTransparency = Alpha; BorderSizePixel = 0;
			Position = UDim2.fromScale(X, Y); Rotation = Rotation or 0; Size = UDim2.fromOffset(W * Size, H * Size);
			ZIndex = Z; Parent = C;
		});
		Round(P, 0.5, 0);
		return P;
	end;

	local Ring = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; BorderSizePixel = 0;
		Position = UDim2.fromScale(0.5, 0.08); Size = UDim2.fromOffset(Size * 0.14, Size * 0.14); ZIndex = Z; Parent = C;
	});
	Round(Ring, 0.5, 0);
	local Stroke = Instance.new('UIStroke');
	Stroke.Color = Color;
	Stroke.Thickness = math.max(1.5, Size * 0.03);
	Stroke.Transparency = Alpha;
	Stroke.Parent = Ring;

	Pill(0.5, 0.2, 0.42, 0.045);       -- stock
	Pill(0.5, 0.56, 0.06, 0.72);       -- shank
	Pill(0.31, 0.83, 0.46, 0.055, 28); -- left arm
	Pill(0.69, 0.83, 0.46, 0.055, -28); -- right arm
	Pill(0.1, 0.72, 0.1, 0.1);         -- flukes
	Pill(0.9, 0.72, 0.1, 0.1);

	return C;
end;

local function BuildFlower(Parent, Size, Color, Center, Z, Alpha)
	local C = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; BorderSizePixel = 0;
		Size = UDim2.fromOffset(Size, Size); ZIndex = Z; Parent = Parent;
	});

	for I = 0, 4 do
		local Pivot = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 0.5); Rotation = I * 72; Size = UDim2.fromScale(1, 1); ZIndex = Z; Parent = C;
		});
		local Petal = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color; BackgroundTransparency = Alpha; BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 0.24); Size = UDim2.fromScale(0.26, 0.42); ZIndex = Z; Parent = Pivot;
		});
		Round(Petal, 0.5, 0);
	end;

	local Core = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Center; BackgroundTransparency = Alpha; BorderSizePixel = 0;
		Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromScale(0.16, 0.16); ZIndex = Z; Parent = C;
	});
	Round(Core, 0.5, 0);

	return C;
end;

-- ---------------------------------------------------------------- scenes
-- Weight tells the user how heavy a scene is: Clean / Balanced / Beautiful / Extreme.
-- Scenes that use pixel geometry (mountains, skyline, sun, clouds, the wind streaks) set Pixel = true so they are
-- rebuilt once after the window has been resized. PanelAlpha = how see-through the groupboxes get in front of it.
-- Every live scene has a Hero (a figure behind the menu, see RM:Hero) and an Accessory (ornaments around the window, see Accessories).

-- [[rig:defs]]
-- the hero of each scene: figure, its four colours, where it stands (window fractions), how big it is and how solid (the store preview uses the same numbers)
local HeroDefs = {
	Vanguard = { Fig = 'Guardian'; Pal = { RGB(255, 92, 98), RGB(122, 14, 28), RGB(255, 190, 180), RGB(255, 240, 220) }; At = { 0.7, 0.5 }; Size = 1; Alpha = 0.86; };
	Void = { Fig = 'Reaper'; Pal = { RGB(176, 150, 255), RGB(20, 10, 44), RGB(218, 206, 255), RGB(170, 255, 225) }; At = { 0.64, 0.52 }; Size = 1; Alpha = 0.8; };
	Ocean = { Fig = 'Ship'; Pal = { RGB(170, 232, 255), RGB(12, 70, 118), RGB(255, 255, 255), RGB(255, 220, 120) }; At = { 0.6, 0.52 }; Size = 1; Alpha = 0.8; };
	Sakura = { Fig = 'Kitsune'; Pal = { RGB(255, 190, 220), RGB(134, 46, 100), RGB(255, 242, 248), RGB(255, 120, 160) }; At = { 0.72, 0.56 }; Size = 1; Alpha = 0.8; };
	Heaven = { Fig = 'Angel'; Pal = { RGB(255, 244, 210), RGB(104, 130, 214), RGB(255, 255, 255), RGB(255, 225, 130) }; At = { 0.62, 0.5 }; Size = 0.96; Alpha = 0.82; };
	Cyber = { Fig = 'Mecha'; Pal = { RGB(0, 229, 255), RGB(10, 28, 56), RGB(170, 250, 255), RGB(255, 43, 214) }; At = { 0.68, 0.56 }; Size = 1; Alpha = 0.8; };
	Inferno = { Fig = 'Phoenix'; Pal = { RGB(255, 160, 50), RGB(138, 28, 8), RGB(255, 232, 130), RGB(255, 255, 205) }; At = { 0.62, 0.52 }; Size = 1.02; Alpha = 0.8; };
	['Deep Sea'] = { Fig = 'Kraken'; Pal = { RGB(60, 255, 215), RGB(6, 50, 72), RGB(175, 255, 240), RGB(255, 90, 190) }; At = { 0.6, 0.5 }; Size = 1.16; Alpha = 0.84; };
};

local function HeroOf(Name)
	local Spec = { Size = 1; Alpha = 0.8; At = { 0.6, 0.5 }; Layer = 'Atmosphere'; };

	for K, V in next, HeroDefs[Name] do
		Spec[K] = V;
	end;

	return Spec;
end;
-- [[/rig:defs]]
-- two shooting stars that cross the sky now and then (scripted: the gap between them is random)
local function ShootingStars(R)
	for I = 1, 2 do
		local Star = R:New('Frame', {
			AnchorPoint = Vector2.new(1, 0.5); BackgroundColor3 = Color3.new(1, 1, 1); Rotation = 28;
			Size = UDim2.fromOffset(80, 2); Visible = false;
		}, R.Layers.Lighting);
		R:New('UIGradient', { Transparency = NS(0, 1, 1, 0); }, Star);

		local NextAt = 2 + I * 2 + FXRandom:NextNumber() * 4;

		R:Tick(function(T)
			if T < NextAt then
				return;
			end;
			NextAt = T + 5 + FXRandom:NextNumber() * 6;

			local StartX, StartY = 0.5 + FXRandom:NextNumber() * 0.45, FXRandom:NextNumber() * 0.25;
			Star.Position = UDim2.fromScale(StartX, StartY);
			Star.BackgroundTransparency = 0;
			Star.Visible = true;

			local Tween = Tw(Star, { Position = UDim2.fromScale(StartX - 0.4, StartY + 0.3); BackgroundTransparency = 1; }, 0.85, Enum.EasingStyle.Quad);
			Tween.Completed:Once(function()
				Star.Visible = false;
			end);
		end, 'Lighting');
	end;
end;

-- small things drifting along a SHORT path next to the window (embers, petals, sparks, bubbles). Spec: Count, Back (behind the window),
-- X / Y (window fractions the path starts at), OffX / OffY (px), Dx / Dy (px travelled), Size, Colors, Alpha (transparency at the start), Dur (s), Shape, Spin
local function AccDrift(A, Spec)
	local R = Spec.Back and A.BackR or A.R;
	local Parent = Spec.Back and A.Back or A.Front;

	for _ = 1, Spec.Count do
		local Px = Roll(Spec.Size or { 3, 5 });
		local X, Y = Roll(Spec.X or { 0, 1 }), Roll(Spec.Y or 1);
		local OffX, OffY = Roll(Spec.OffX or 0), Roll(Spec.OffY or 0);
		local Dx, Dy = Roll(Spec.Dx or { -20, 20 }), Roll(Spec.Dy or { -40, -20 });

		local F = R:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Spec.Colors[FXRandom:NextInteger(1, #Spec.Colors)];
			BackgroundTransparency = Spec.Alpha or 0.1; Size = UDim2.fromOffset(Px * (Spec.Shape == 'Petal' and 1.7 or 1), Px);
		}, Parent);

		if Spec.Shape ~= 'Square' then
			Round(F, 0.5, 0);
		end;

		local Dur = Roll(Spec.Dur or { 1.4, 3 });
		R:Cycle(F, { Position = { UDim2.new(X, OffX, Y, OffY), UDim2.new(X, OffX + Dx, Y, OffY + Dy) }; BackgroundTransparency = { Spec.Alpha or 0.1, 1 }; }, Dur, 'Decor');

		if Spec.Spin then
			R:Cycle(F, { Rotation = { 0, Spec.Spin > 0 and 360 or -360 } }, 360 / math.max(math.abs(Spec.Spin), 10), 'Decor');
		end;
	end;
end;
-- a flame for the accessories: a round body with a pointed tip, three layers from red to white-hot, swaying
-- Back = behind the window. Pos = UDim2 of the base centre, Rot = degrees it leans
local function AccFlame(A, Back, Pos, Wd, Ht, Rot)
	local R = Back and A.BackR or A.R;
	local Parent = Back and A.Back or A.Front;
	local Piv = A:Pivot(Parent, Pos, Rot);
	local Piece = A:Canvas(Piv, { AnchorPoint = Vector2.new(0.5, 1); Position = UDim2.fromOffset(0, 0); Size = UDim2.fromOffset(Wd, Ht); }, Back);
	local Layers = { { 1, RGB(255, 60, 12) }, { 0.74, RGB(255, 150, 34) }, { 0.46, RGB(255, 236, 150) } };

	for _, L in ipairs(Layers) do
		local K = L[1];
		local Body = R:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 1); BackgroundColor3 = L[2]; Position = UDim2.new(0.5, 0, 1, -1);
			Size = UDim2.fromOffset(Wd * K, Ht * 0.58 * K);
		}, Piece);
		Round(Body, 0.5, 0);

		local Side = Wd * 0.64 * K;
		local Tip = R:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = L[2]; Position = UDim2.new(0.5, 0, 1, -(Ht * 0.58 * K) - Side * 0.1 + (1 - K) * 0);
			Rotation = 45; Size = UDim2.fromOffset(Side, Side);
		}, Piece);
		Tip.Position = UDim2.new(0.5, 0, 1, -Ht * K + Side * 0.707);
		Round(Tip, 0, 2);
	end;

	local Scale = Instance.new('UIScale');
	Scale.Parent = Piv;
	R:Sway(Scale, { Scale = { 0.84, 1.08 } }, Roll({ 0.25, 0.5 }), 'Decor');
	R:Sway(Piv, { Rotation = { Rot - 5, Rot + 5 } }, Roll({ 0.3, 0.6 }), 'Decor');
	return Piv;
end;

FX:RegisterScene({
	Name = 'Vanguard'; Category = 'Military'; Weight = 'Extreme'; Transition = 'Scan'; Pixel = true; PanelAlpha = 0.34;
	Description = 'The red Guardian: an armoured warrior with blade wings, a crimson sun, searchlights, shockwaves and rising shards';
	Build = function(R)
		R:Gradient({
			Layer = 'Base'; Rotation = 90; Drift = 0.12; DriftAmount = 0.06;
			Colors = Seq(RGB(14, 2, 8), RGB(58, 8, 20), RGB(136, 22, 34), RGB(214, 46, 48));
		});

		-- the red sun behind the Guardian and the light falling from above
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(255, 60, 70); Size = 560; X = 0.58; Y = 0.4; Alpha = 0.935; Rings = 12; Pulse = { 0.9, 0.06 }; });
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(255, 70, 70); Size = 640; X = 0.5; Y = 1.02; Alpha = 0.94; Rings = 10; Pulse = { 1.2, 0.06 }; });
		R:Rays({ Count = 6; Color = RGB(255, 110, 110); Width = { 30, 80 }; X = { 0.2, 0.95 }; Sway = 5; Start = 0.8; });

		R:Hero(HeroOf('Vanguard'));

		R:Beam({ Layer = 'Atmosphere'; X = 0.12; Color = RGB(255, 120, 120); Alpha = 0.7; Sweep = { -12, 38 }; Seconds = 7; });
		R:Beam({ Layer = 'Atmosphere'; X = 0.88; Color = RGB(255, 120, 120); Alpha = 0.7; Sweep = { 12, -38 }; Seconds = 8.5; });
		R:Pulse({ Layer = 'Atmosphere'; X = 0.58; Y = 0.95; Count = 4; Min = 80; Max = 760; Period = 5; Color = RGB(255, 80, 90); Alpha = 0.45; Thickness = 2; });
		R:Smoke({ Layer = 'Atmosphere'; Count = 7; Size = { 140, 220 }; Speed = { 0.014, 0.03 }; Color = RGB(60, 12, 18); Alpha = 0.92; });
		R:Vignette({ Layer = 'Atmosphere'; Strength = 0.55; });

		R:Emitter({ -- chevrons rising
			Shape = 'Text'; Count = 14; Size = { 14, 20 }; Vx = { -0.004, 0.004 }; Vy = { -0.1, -0.04 }; Alpha = { 0.45, 0.8 };
			Chars = '^V>'; Column = 4; Colors = { RGB(255, 90, 100), RGB(255, 150, 150) };
		});
		R:Emitter({ -- blade shards drifting up
			Shape = 'Diamond'; Count = 14; Size = { 6, 14 }; Vx = { -0.012, 0.012 }; Vy = { -0.07, -0.02 }; Spin = { -90, 90 };
			Alpha = { 0.6, 0.9 }; LifeFade = true; Colors = { RGB(255, 90, 100), RGB(255, 190, 190) };
		});
		R:Emitter({
			Shape = 'Circle'; Count = 28; Size = { 1.5, 3.5 }; Vx = { -0.02, 0.02 }; Vy = { -0.2, -0.07 };
			Alpha = { 0.5, 0.9 }; Twinkle = 0.5; LifeFade = true; Colors = { RGB(255, 110, 100), RGB(255, 190, 150) };
		});

		R:Lightning({ Layer = 'Lighting'; Color = RGB(255, 80, 90); Period = { 5, 9 }; Reach = 0.6; Flash = 0.2; });
		R:Scanner({ Color = RGB(255, 90, 100); Period = 7; });
	end;

	-- a winged crest of blades on the top edge, blade spikes on the four corners, a neon trim under the window. Armour only, no flags
	Accessory = function(A)
		local Pal = { RGB(255, 92, 98), RGB(122, 14, 28), RGB(255, 190, 180), RGB(255, 240, 220) };
		local S = A.Scale;

		A:Art('VanCrest', Pal, UDim2.new(0.5, 0, 0, 0), 110 * S, { Back = true; View = { -1.2, -0.62, 2.4, 1.24 }; });

		for _, C in ipairs({
			{ 'VanSpikeL', 0, 0, 0, 0 }, { 'VanSpike', 1, 0, 0, 0 }, { 'VanSpikeBL', 0, 0, 1, 0 }, { 'VanSpikeB', 1, 0, 1, 0 },
		}) do
			A:Art(C[1], Pal, UDim2.new(C[2], C[3], C[4], C[5]), 62 * S, { Back = true; });
		end;

		-- two long swords stand behind the window, one at each side, hilt down. They swing when the window moves and when something kicks
		-- (the pommel ends just under the window, the tip rises 50px over the top edge)
		local WinH = A.Size.Y;
		local SU = (WinH - 35 + 50) / 2;
		for _, C in ipairs({ { 'VanSwordL', 0, -2, -1 }, { 'VanSword', 1, 2, 1 } }) do
			local Pivot = A:Art(C[1], Pal, UDim2.new(C[2], C[3], 0, WinH - 35), SU, { Back = true; View = { -0.3, -2.05, 0.6, 2.3 }; });
			if Pivot then
				A:Spring(Pivot, { Side = C[4]; GX = 0.35; GY = 0.55; K = 42; C = 3.4; Max = 9; IdleAmp = 0.7; IdleSpeed = 0.9; });
			end;
		end;

		-- the trim: a thin red light just under the window with a bright spot running along it
		local Trim = A.R:New('Frame', {
			BackgroundColor3 = RGB(255, 70, 80); Position = UDim2.new(0, 10, 1, 3); Size = UDim2.new(1, -20, 0, 3);
		}, A.Front);
		Round(Trim, 0.5, 0);
		A.R:New('UIGradient', { Transparency = NS(0, 0.85, 0.5, 0, 1, 0.85); }, Trim);

		local Run = A.R:New('Frame', {
			BackgroundColor3 = Color3.new(1, 1, 1); Position = UDim2.new(0, 0, 0, -1); Size = UDim2.new(0, 90, 0, 5);
		}, Trim);
		Round(Run, 0.5, 0);
		A.R:New('UIGradient', { Transparency = NS(0, 1, 0.5, 0, 1, 1); }, Run);
		A.R:Cycle(Run, { Position = { UDim2.new(0, -100, 0, -1), UDim2.new(1, 10, 0, -1) } }, 3.2, 'Decor', 0);

		AccDrift(A, { Count = 8; X = { 0.02, 0.98 }; Y = 1; OffY = 6; Dx = { -20, 20 }; Dy = { 14, 34 }; Size = { 2, 4 }; Shape = 'Square'; Colors = { RGB(255, 110, 100), RGB(255, 190, 150) }; Dur = { 1.4, 2.8 }; });
	end;
});

FX:RegisterScene({
	Name = 'Void'; Category = 'Dark'; Weight = 'Balanced'; Transition = 'Fade'; PanelAlpha = 0.14;
	Description = 'A dark rift: a hooded reaper, aurora ribbons, ripples, violet lightning and slow motes';
	Build = function(R)
		R:Gradient({
			Layer = 'Base'; Rotation = 90; Drift = 0.1; DriftAmount = 0.08;
			Colors = Seq(RGB(18, 10, 40), RGB(6, 4, 16), RGB(2, 2, 8));
		});

		R:Glow({ Layer = 'Atmosphere'; Color = RGB(130, 100, 255); Size = 460; X = 0.5; Y = 0.45; Alpha = 0.955; Rings = 10; Pulse = { 0.5, 0.07 }; });
		R:Curtain({ Layer = 'Atmosphere'; Count = 4; Width = { 90, 170 }; X = { 0.1, 0.9 }; Height = 0.8; Colors = { RGB(140, 100, 255), RGB(90, 60, 220) }; Alpha = 0.82; });
		R:Hero(HeroOf('Void'));
		R:Pulse({ Layer = 'Atmosphere'; X = 0.5; Y = 0.45; Count = 4; Min = 60; Max = 560; Period = 7; Color = RGB(140, 110, 255); Alpha = 0.5; Thickness = 2; });
		R:Smoke({ Layer = 'Atmosphere'; Count = 7; Size = { 150, 230 }; Speed = { 0.01, 0.02 }; Color = RGB(90, 60, 190); Alpha = 0.94; });
		R:Vignette({ Layer = 'Atmosphere'; Strength = 0.7; });

		R:Emitter({
			Shape = 'Circle'; Count = 22; Size = { 1, 3 }; Vx = { -0.003, 0.003 }; Vy = { -0.014, -0.004 };
			Alpha = { 0.5, 0.85 }; Twinkle = 0.6; Colors = { RGB(170, 150, 255) };
		});
		R:Emitter({ -- far stars
			Layer = 'Decor'; Shape = 'Circle'; Count = 36; Size = { 1, 2.4 }; Static = true; Alpha = { 0.3, 0.8 }; Twinkle = 0.9;
			Colors = { RGB(190, 170, 255), RGB(255, 255, 255) };
		});
		R:Lightning({ Layer = 'Lighting'; Color = RGB(150, 110, 255); Period = { 5, 9 }; Reach = 0.8; Flash = 0.22; });
	end;

	-- obsidian shards floating around the edge (behind the window) and a watching eye over the top
	Accessory = function(A)
		local B, S = A.BackR, A.Scale;
		local W, H = A.Size.X, A.Size.Y;

		for _, C in ipairs({
			{ UDim2.new(0, -4, 0, 4), 22, 40, -12, 3.2 }, { UDim2.new(1, 4, 0, -2), 26, 46, 14, 3.8 }, { UDim2.new(0, -8, 0.58, 0), 20, 36, 20, 4.2 },
			{ UDim2.new(1, 8, 0.64, 0), 18, 34, -22, 3.6 }, { UDim2.new(0.18, 0, 1, 8), 18, 32, 8, 3 }, { UDim2.new(0.82, 0, 1, 10), 20, 36, -10, 3.4 },
		}) do
			local Pos, Wd, Ht, Rot, Secs = C[1], C[2] * S, C[3] * S, C[4], C[5];
			local Shard = B:New('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = Color3.new(1, 1, 1); Position = Pos; Rotation = Rot; Size = UDim2.fromOffset(Wd, Ht);
			}, A.Back);
			Round(Shard, 0.4, 0);
			B:New('UIGradient', { Rotation = 70; Color = Seq(RGB(190, 170, 255), RGB(40, 20, 90)); }, Shard);
			B:Sway(Shard, { Position = { Pos, Pos - UDim2.fromOffset(0, 10) }; Rotation = { Rot, Rot + 12 }; }, Secs * 0.5, 'Decor');
		end;

		local Eye, Piece = A:Art('Eye', { RGB(190, 170, 255), RGB(24, 12, 54), RGB(255, 255, 255), RGB(130, 100, 255) }, UDim2.new(0.5, 0, 0, -12), 44 * S, {});
		if Piece then
			local P0 = Piece.Position;
			A.R:Sway(Piece, { Position = { P0, P0 - UDim2.fromOffset(0, 4) } }, 2.2, 'Decor');
		end;
	end;
});

FX:RegisterScene({
	Name = 'Ocean'; Category = 'Nature'; Weight = 'Balanced'; Transition = 'Ripple'; PanelAlpha = 0.34;
	Description = 'Underwater: a galleon, a passing whale, caustics, surface waves, light shafts, fish, kelp, bubbles';
	Build = function(R)
		R:Gradient({
			Layer = 'Base'; Rotation = 90; Drift = 0.18; DriftAmount = 0.12;
			Colors = Seq(RGB(24, 178, 222), RGB(10, 104, 176), RGB(5, 52, 112), RGB(3, 26, 66));
		});

		R:Rays({ Count = 7; Color = RGB(200, 250, 255); Width = { 34, 80 }; X = { 0.06, 0.94 }; Sway = 5; Start = 0.72; });
		R:Hero(HeroOf('Ocean'));
		R:Whale({ Layer = 'Decor'; Y = 0.46; Size = (R:Size().X) * 0.52; Color = RGB(8, 56, 112); Alpha = 0.66; Seconds = 70; });
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(200, 255, 255); Size = 520; X = 0.5; Y = 0.0; Alpha = 0.955; Rings = 10; Pulse = { 0.6, 0.08 }; });
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(40, 200, 230); Size = 300; X = 0.2; Y = 0.55; Alpha = 0.95; Pulse = { 0.5, 0.1 }; Drift = { 0.04, 0.03, 0.2 }; });
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(20, 120, 230); Size = 340; X = 0.82; Y = 0.7; Alpha = 0.95; Pulse = { 0.4, 0.1 }; Drift = { 0.04, 0.04, 0.16 }; });
		R:Caustics({ Layer = 'Atmosphere'; Count = 14; Depth = 0.5; Color = RGB(220, 255, 255); Alpha = 0.86; });

		-- the surface, seen from below: three bright swells with white foam along their lower edge
		R:Waves({
			Layer = 'Atmosphere'; Top = true; Segments = 84;
			Bands = {
				{ Body = RGB(60, 190, 235); Crest = RGB(230, 255, 255); Alpha = 0.45; Height = 0.095; Amp = 0.016; Speed = 0.7; Freq = 0.38; };
				{ Body = RGB(110, 215, 245); Crest = RGB(255, 255, 255); Alpha = 0.5; Height = 0.07; Amp = 0.014; Speed = -0.9; Freq = 0.45; };
				{ Body = RGB(170, 240, 255); Crest = RGB(255, 255, 255); Alpha = 0.45; Height = 0.045; Amp = 0.012; Speed = 1.1; Freq = 0.55; };
			};
		});

		R:Fish({ Layer = 'Decor'; Count = 12; Per = 4; Y = { 0.35, 0.7 }; Colors = { RGB(255, 170, 60), RGB(120, 235, 255), RGB(255, 215, 90) }; Alpha = 0.22; });
		R:Fish({ Layer = 'Decor'; Count = 8; Per = 4; Y = { 0.22, 0.86 }; Size = { 11, 16 }; Speed = { 0.024, 0.044 }; Colors = { RGB(200, 245, 255), RGB(255, 200, 120) }; Alpha = 0.4; }); -- a few smaller, slower ones
		R:Kelp({ Layer = 'Decor'; Count = 12; Height = { 70, 140 }; Color = RGB(10, 110, 70); Tip = RGB(90, 230, 150); });

		local Anchor = BuildAnchor(R.Layers.Decor, 90, RGB(170, 225, 255), R.Z, 0.8);
		Anchor.Position = UDim2.fromScale(0.07, 0.8);
		R:Sway(Anchor, { Rotation = { -7, 7 } }, 3.2, 'Decor');

		R:Emitter({
			Shape = 'Bubble'; Count = 26; Size = { 4, 13 }; Vx = { -0.005, 0.005 }; Vy = { -0.12, -0.04 };
			Alpha = { 0.35, 0.8 }; Wobble = { 0.012, 1.3, 2.3 }; Colors = { RGB(220, 250, 255) };
		});
		R:Emitter({ -- drifting plankton
			Shape = 'Circle'; Count = 30; Size = { 1, 2.5 }; Vx = { -0.01, 0.01 }; Vy = { -0.02, 0.02 };
			Alpha = { 0.4, 0.8 }; Twinkle = 0.7; Colors = { RGB(230, 255, 255) };
		});
	end;

	-- coral under the bottom corners, a bubble stream
	Accessory = function(A)
		local S = A.Scale;

		for _, C in ipairs({ { 0, 6, RGB(255, 120, 150) }, { 1, -80, RGB(255, 170, 90) } }) do
			for I = 0, 4 do
				local Ht = (34 + (I % 3) * 7) * S;
				local Coral = A.R:New('Frame', {
					AnchorPoint = Vector2.new(0.5, 1); BackgroundColor3 = C[3]; Position = UDim2.new(C[1], C[2] + I * 15, 1, 34); Rotation = (I - 2) * 12; Size = UDim2.fromOffset(15 * S, Ht);
				}, A.Front);
				Round(Coral, 0.4, 0);
				A.R:New('UIGradient', { Rotation = 90; Color = Seq(RGB(255, 255, 255), C[3]); }, Coral);
				A.R:Sway(Coral, { Rotation = { (I - 2) * 12 - 4, (I - 2) * 12 + 4 } }, Roll({ 2, 3.4 }), 'Decor');
			end;
		end;

		AccDrift(A, { Count = 10; X = 1; Y = { 0.95, 1 }; OffX = { -16, 14 }; Dx = { -22, 10 }; Dy = { -260, -150 }; Size = { 5, 11 }; Alpha = 0.55; Colors = { RGB(230, 252, 255) }; Dur = { 3.2, 5.2 }; });
	end;
});

FX:RegisterScene({
	Name = 'Sakura'; Category = 'Nature'; Weight = 'Beautiful'; Transition = 'Petals'; Pixel = true; PanelAlpha = 0.32;
	Description = 'A blossom storm: a nine tailed fox spirit, petals and whole flowers on the wind, light rays, moonlit pink haze';
	Build = function(R)
		R:Gradient({
			Layer = 'Base'; Rotation = 90; Drift = 0.16; DriftAmount = 0.1;
			Colors = Seq(RGB(40, 12, 76), RGB(132, 40, 120), RGB(232, 100, 150), RGB(255, 176, 184));
		});

		-- moonlight, with soft pink beams falling through the haze
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(255, 226, 240); Size = 460; X = 0.8; Y = 0.15; Alpha = 0.95; Rings = 10; Pulse = { 0.35, 0.05 }; });
		local Moon = R:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = RGB(255, 240, 246); BackgroundTransparency = 0.08;
			Position = UDim2.fromScale(0.8, 0.15); Size = UDim2.fromOffset(64, 64);
		}, R.Layers.Atmosphere);
		Round(Moon, 0.5, 0);
		R:Rays({ Count = 5; Color = RGB(255, 205, 228); Width = { 40, 92 }; X = { 0.4, 0.98 }; Sway = 6; Start = 0.82; });
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(255, 110, 160); Size = 400; X = 0.1; Y = 0.92; Alpha = 0.95; Pulse = { 0.5, 0.08 }; Drift = { 0.03, 0.02, 0.15 }; });
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(190, 90, 230); Size = 360; X = 0.3; Y = 0.25; Alpha = 0.96; Pulse = { 0.4, 0.07 }; Drift = { 0.04, 0.03, 0.12 }; });

		R:Hero(HeroOf('Sakura'));

		-- haze along the ground and gusts of wind sweeping through
		R:Smoke({ Layer = 'Atmosphere'; Count = 6; Size = { 170, 260 }; Speed = { 0.01, 0.022 }; Color = RGB(255, 190, 215); Alpha = 0.955; });
		R:Wind({ Layer = 'Atmosphere'; Count = 7; Color = RGB(255, 226, 238); Length = { 200, 380 }; Thick = { 2, 4 }; Alpha = { 0.82, 0.93 }; Duration = { 5, 9 }; Drop = 0.2; });

		local Pink = { RGB(255, 170, 200), RGB(255, 205, 225), RGB(255, 140, 180), RGB(255, 235, 242) };

		-- the nearest petals: huge and soft, out of focus, they sweep across the glass
		R:Emitter({
			Layer = 'Lighting'; Shape = 'Petal'; Count = 6; Size = { 24, 42 }; Vx = { -0.1, -0.05 }; Vy = { 0.09, 0.15 }; Spin = { -60, 60 };
			Flip = { 1.4, 2.4 }; Gradient = true; Wobble = { 0.04, 0.5, 0.9 }; Alpha = { 0.45, 0.65 };
			Spawn = { X = { 0.5, 1.0 }; Y = { -0.05, 0.3 } }; Colors = Pink;
		});

		-- whole five-petal blossoms, turning slowly as the wind carries them
		R:Emitter({
			Layer = 'Particles'; Shape = 'Flower'; Count = 8; Size = { 26, 46 }; Vx = { -0.07, -0.025 }; Vy = { 0.05, 0.1 }; Spin = { -50, 50 };
			Wobble = { 0.03, 0.6, 1.2 }; Spawn = { X = { 0.35, 1.0 }; Y = { -0.05, 0.35 } };
			Colors = { RGB(255, 150, 190), RGB(255, 190, 215), RGB(255, 125, 170) };
			Build = function(Rr, Mover, Px, Color)
				return BuildFlower(Mover, Px, Color, RGB(255, 240, 200), Rr.Z, 0.05);
			end;
		});

		R:Emitter({ -- sparkles in the moonlight
			Layer = 'Lighting'; Shape = 'Diamond'; Count = 10; Size = { 3, 6 }; Static = true; Alpha = { 0.3, 0.7 };
			Twinkle = 0.85; Colors = { RGB(255, 235, 245), RGB(255, 225, 190) };
		});

		-- the storm itself: tumbling petals, lighter at the base
		R:Emitter({
			Layer = 'Particles'; Shape = 'Petal'; Count = 26; Size = { 8, 15 }; Vx = { -0.07, -0.02 }; Vy = { 0.05, 0.11 }; Spin = { -120, 120 };
			Flip = { 0.9, 1.8 }; Gradient = true; Wobble = { 0.025, 0.7, 1.5 }; Alpha = { 0.05, 0.3 };
			Spawn = { X = { 0.3, 1.0 }; Y = { -0.05, 0.4 } }; Colors = Pink;
		});

		-- far away: small, pale petals behind everything
		R:Emitter({
			Layer = 'Decor'; Shape = 'Petal'; Count = 18; Size = { 3, 6 }; Vx = { -0.045, -0.015 }; Vy = { 0.03, 0.06 }; Spin = { -70, 70 };
			Flip = { 1.2, 2.2 }; Wobble = { 0.015, 0.5, 1 }; Alpha = { 0.3, 0.6 }; Colors = { RGB(240, 170, 210), RGB(250, 200, 230) };
		});

		-- a carpet of fallen petals along the bottom edge
		R:Emitter({
			Layer = 'Decor'; Shape = 'Petal'; Count = 16; Size = { 5, 10 }; Static = true; Alpha = { 0.1, 0.35 };
			Spawn = { X = { 0, 1 }; Y = { 0.93, 1.0 } }; Colors = Pink;
		});

		R:Glow({ Color = RGB(255, 180, 210); Size = 320; X = 0.85; Y = 0.3; Alpha = 0.965; Pulse = { 0.5, 0.06 }; });
	end;

	-- short blossom garlands over the top corners, a glowing lantern, petals falling along the edges
	Accessory = function(A)
		local R, S = A.R, A.Scale;
		local Lights = { RGB(255, 168, 200), RGB(255, 200, 222) };

		for _, Side in ipairs({ 0, 1 }) do
			for K = 0, 1 do
				local Dx = (16 + K * 34);
				local Len = (40 + K * 14) * S;
				local Piv = A:Pivot(A.Front, UDim2.new(Side, Side == 0 and Dx or -Dx, 0, -50 * S), 0);

				local Cord = R:New('Frame', { BackgroundColor3 = RGB(255, 190, 215); BackgroundTransparency = 0.2; Position = UDim2.fromOffset(-1, 0); Size = UDim2.fromOffset(2, Len); }, Piv);
				R:New('UIGradient', { Rotation = 90; Transparency = NS(0, 0.1, 1, 0.6); }, Cord);

				for I = 0, 2 + K do
					local Flower = BuildFlower(Piv, (20 - I * 1.5) * S, Lights[I % 2 + 1], RGB(255, 236, 170), R.Z, 0);
					Flower.Position = UDim2.fromOffset(I % 2 == 1 and 5 or -5, 8 + I * (Len / (3 + K)));
				end;

				R:Sway(Piv, { Rotation = { -5, 5 } }, 2.6 + K * 0.5, 'Decor');
			end;
		end;

		-- the lantern
		local Lan = A:Pivot(A.Front, UDim2.new(0.5, 0, 0, -56 * S), 0);
		R:New('Frame', { BackgroundColor3 = RGB(255, 210, 230); BackgroundTransparency = 0.2; Position = UDim2.fromOffset(-1, 0); Size = UDim2.fromOffset(2, 22 * S); }, Lan);
		local Glass = R:New('Frame', {
			AnchorPoint = Vector2.new(0.5, 0); BackgroundColor3 = RGB(255, 190, 200); Position = UDim2.fromOffset(0, 22 * S); Size = UDim2.fromOffset(34 * S, 40 * S);
		}, Lan);
		Round(Glass, 0.3, 0);
		R:New('UIGradient', { Rotation = 90; Color = Seq(RGB(255, 250, 220), RGB(255, 140, 170)); }, Glass);
		R:Glow({ Layer = 'Decor'; Color = RGB(255, 150, 190); Size = 90 * S; X = 0.5; Y = -0.07; Alpha = 0.93; Rings = 6; });
		R:Sway(Glass, { BackgroundTransparency = { 0, 0.2 } }, 1.4, 'Decor');
		R:Sway(Lan, { Rotation = { -4, 4 } }, 3.2, 'Decor');

		AccDrift(A, { Count = 8; X = { 0, 1 }; Y = 0; OffY = { -50, -6 }; Dx = { -90, -30 }; Dy = { 90, 160 }; Size = { 8, 14 }; Shape = 'Petal'; Spin = 120; Alpha = 0.1; Colors = { RGB(255, 185, 210), RGB(255, 215, 230) }; Dur = { 4.2, 7 }; });
	end;
});

FX:RegisterScene({
	Name = 'Heaven'; Category = 'Fantasy'; Weight = 'Beautiful'; Transition = 'Light'; Pixel = true; PanelAlpha = 0.3;
	Description = 'An angel standing on a holy cloud in the sky: layered clouds, light rays, a halo sun, falling feathers, a celestial scale, a crucifix and holy clouds around the window';
	Build = function(R)
		R:Gradient({
			Layer = 'Base'; Rotation = 90; Drift = 0.12; DriftAmount = 0.1;
			Colors = Seq(RGB(38, 88, 214), RGB(104, 160, 246), RGB(255, 206, 150), RGB(255, 168, 108));
		});

		R:Glow({ Layer = 'Atmosphere'; Color = RGB(255, 236, 170); Size = 600; X = 0.5; Y = 0.02; Alpha = 0.93; Rings = 10; Pulse = { 0.5, 0.07 }; });
		R:Rays({ Count = 9; Color = RGB(255, 240, 190); Width = { 34, 84 }; X = { 0.06, 0.94 }; Sway = 4; Start = 0.5; });
		R:Hero(HeroOf('Heaven'));
		R:Pulse({ Layer = 'Atmosphere'; X = 0.5; Y = 0.0; Count = 3; Min = 120; Max = 520; Period = 5; Color = RGB(255, 236, 170); Alpha = 0.45; Thickness = 3; });

		-- two cloud layers: a thin far one, a thick near one that drifts faster (parallax)
		R:Clouds({ Count = 4; Width = { 0.2, 0.32 }; Alpha = 0.5; Y = { 0.5, 0.8 }; Speed = { 0.003, 0.006 }; });
		R:Clouds({ Count = 4; Width = { 0.22, 0.36 }; Alpha = 0.15; Y = { 0.66, 0.92 }; Speed = { 0.006, 0.011 }; });

		R:Emitter({ -- sparkles in the sky
			Layer = 'Decor'; Shape = 'Diamond'; Count = 12; Size = { 3, 6 }; Static = true; Alpha = { 0.3, 0.7 };
			Twinkle = 0.8; Colors = { RGB(255, 250, 220) };
		});
		R:Emitter({ -- golden motes rising
			Shape = 'Circle'; Count = 26; Size = { 2, 6 }; Vx = { -0.004, 0.004 }; Vy = { -0.05, -0.018 };
			Alpha = { 0.2, 0.6 }; Twinkle = 0.7; Colors = { RGB(255, 240, 200), RGB(255, 255, 255) };
		});
		R:Emitter({ -- feathers floating down
			Shape = 'Petal'; Count = 14; Size = { 5, 9 }; Vx = { -0.01, 0.015 }; Vy = { 0.03, 0.07 }; Spin = { -40, 40 };
			Flip = { 1.2, 2.2 }; Wobble = { 0.02, 0.5, 1 }; Alpha = { 0.05, 0.3 }; Colors = { RGB(255, 255, 255), RGB(255, 244, 214) };
		});
	end;

	-- a celestial scale over the top edge (the beam and the two pans swing together), a crucifix and a holy cloud at the top corners, holy clouds under
	-- the bottom corners. Gold and white, everything slow. Pieces sit behind the window, so they never cover the menu.
	Accessory = function(A)
		local B, S = A.BackR, A.Scale;
		local Pal = { RGB(255, 236, 170), RGB(176, 150, 70), RGB(255, 252, 236), RGB(255, 225, 130) };

		-- the scale: one slow rock, the pans rise and fall against the beam and tilt a little
		local U, By, Half = 48 * S, -38 * S, 3.4;
		local Beam = A:Art('ScaleBeam', Pal, UDim2.new(0.5, 0, 0, By), U, { Back = true; View = { -1.1, -0.55, 2.2, 0.75 }; });
		if Beam then
			Beam.Rotation = -4;
			B:Tween(Beam, { Rotation = 4 }, Half, Enum.EasingStyle.Sine, EInOut, 'Decor', -1, true);
		end;

		for _, C in ipairs({ { -1, 3.4, 2.4 }, { 1, -3.4, -2.4 } }) do
			local Pan = A:Art('ScalePan', Pal, UDim2.new(0.5, C[1] * 0.9 * U, 0, By), U, { Back = true; View = { -0.45, -0.05, 0.9, 0.85 }; });
			if Pan then
				local Home = Pan.Position;
				Pan.Position = Home + UDim2.fromOffset(0, C[2]);
				Pan.Rotation = C[3];
				B:Tween(Pan, { Position = Home - UDim2.fromOffset(0, C[2]); Rotation = -C[3]; }, Half, Enum.EasingStyle.Sine, EInOut, 'Decor', -1, true);
			end;
		end;

		-- the crucifix (top left): light pulses behind it, it sways like something hung
		B:Glow({ Layer = 'Decor'; Color = RGB(255, 236, 170); Size = 70 * S; X = 34 * S / A.Size.X; Y = -34 * S / A.Size.Y; Alpha = 0.9; Rings = 8; Pulse = { 1.05, 0.12 }; });
		local Cross = A:Art('HolyCross', Pal, UDim2.new(0, 34 * S, 0, -34 * S), 26 * S, { Back = true; View = { -0.7, -1.1, 1.4, 2.2 }; Pivot = Vector2.new(0, 0.95); });
		if Cross then
			A:Spring(Cross, { Side = -1; GX = 0.4; GY = 0.5; K = 40; C = 3.4; Max = 6; IdleAmp = 1.2; IdleSpeed = 0.8; });
		end;

		-- holy clouds drift slowly: top right, and under the bottom corners
		for I, C in ipairs({ { UDim2.new(1, -44 * S, 0, -16 * S), 34, 8.2 }, { UDim2.new(0, 48 * S, 1, 12 * S), 40, 9.6 }, { UDim2.new(1, -52 * S, 1, 14 * S), 36, 7.6 } }) do
			local Cloud = A:Art('HolyCloud', Pal, C[1], C[2] * S, { Back = true; View = { -1.1, -0.6, 2.2, 0.95 }; });
			if Cloud then
				local Home = Cloud.Position;
				Cloud.Position = Home - UDim2.fromOffset(12, 0);
				B:Tween(Cloud, { Position = Home + UDim2.fromOffset(12, I % 2 == 0 and -4 or 4) }, C[3], Enum.EasingStyle.Sine, EInOut, 'Decor', -1, true, FXRandom:NextNumber() * C[3]);
			end;
		end;
	end;
});

FX:RegisterScene({
	Name = 'Cyber'; Category = 'Technology'; Weight = 'Extreme'; Transition = 'Scan'; Pixel = true; PanelAlpha = 0.36;
	Description = 'A mech in front of a synthwave sun: skyline, neon grid, digital rain, scan line. No floating decorations';
	Build = function(R)
		local Cyan, Magenta = RGB(0, 229, 255), RGB(255, 43, 214);

		R:Gradient({
			Layer = 'Base'; Rotation = 90;
			Colors = function()
				return ColorSequence.new({
					ColorSequenceKeypoint.new(0, RGB(14, 0, 40)), ColorSequenceKeypoint.new(0.3, RGB(58, 0, 92)),
					ColorSequenceKeypoint.new(0.4, RGB(255, 40, 150)), ColorSequenceKeypoint.new(0.41, RGB(16, 0, 40)),
					ColorSequenceKeypoint.new(1, RGB(6, 0, 28)),
				});
			end;
		});

		R:Glow({ Layer = 'Atmosphere'; Color = RGB(255, 60, 170); Size = 560; X = 0.5; Y = 0.4; Alpha = 0.945; Rings = 10; Pulse = { 1, 0.05 }; });
		R:Sun({ X = 0.5; Y = 0.23; Size = 240; Bars = 28; Top = RGB(255, 238, 100); Bottom = RGB(255, 40, 150); });
		R:Hero(HeroOf('Cyber'));
		R:Skyline({ Y = 0.4; Color = RGB(10, 2, 30); Edge = Cyan; Lights = { Cyan, Magenta, RGB(255, 230, 90) }; });
		R:Grid({ Color = Magenta; Horizon = 0.4; Lines = 12; Spread = 0.18; Rows = 12; });

		R:Emitter({ -- digital rain
			Shape = 'Text'; Count = 14; Size = { 10, 14 }; Vx = { -0.002, 0.002 }; Vy = { 0.16, 0.34 }; Alpha = { 0.2, 0.45 };
			Chars = '01$#%&<>=+'; Column = 8; Colors = { Cyan, RGB(0, 255, 170) };
		});
		R:Emitter({
			Shape = 'Square'; Count = 18; Size = { 2, 4 }; Vx = { -0.01, 0.01 }; Vy = { -0.07, -0.02 };
			Alpha = { 0.3, 0.7 }; Twinkle = 0.6; Colors = { Cyan, Magenta };
		});

		R:Scanner({ Color = Cyan; Period = 6; });
		R:Glow({ Color = Magenta; Size = 300; X = 0.85; Y = 0.9; Alpha = 0.955; Pulse = { 0.8, 0.06 }; });
	end;

});

FX:RegisterScene({
	Name = 'Inferno'; Category = 'Fantasy'; Weight = 'Extreme'; Transition = 'Flame'; Pixel = true; PanelAlpha = 0.38;
	Description = 'A phoenix over lava waves and a volcano, smoke, falling ash and rising embers';
	Build = function(R)
		R:Gradient({
			Layer = 'Base'; Rotation = 90; Drift = 0.2; DriftAmount = 0.08;
			Colors = Seq(RGB(26, 6, 8), RGB(92, 16, 10), RGB(176, 44, 8), RGB(255, 112, 18));
		});

		R:Mountains({ Items = {
			{ X = 0.16; Height = 0.39; Color = RGB(34, 9, 8); };
			{ X = 0.86; Height = 0.31; Color = RGB(40, 10, 8); };
			{ X = 0.53; Height = 0.555; Color = RGB(22, 6, 6); };
		}; });

		R:Hero(HeroOf('Inferno'));

		-- the crater glows and flickers
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(255, 160, 40); Size = 420; X = 0.53; Y = 0.445; Alpha = 0.93; Rings = 10; Pulse = { 2.4, 0.08 }; });

		R:Smoke({ Layer = 'Atmosphere'; Count = 10; Size = { 90, 150 }; Speed = { 0.025, 0.055 }; Color = RGB(34, 12, 10); Alpha = 0.925; });

		-- four lava swells, back (deep red) to front (white-hot crest)
		R:Waves({
			Layer = 'Atmosphere'; Segments = 96;
			Bands = {
				{ Body = RGB(150, 18, 8); Crest = RGB(255, 110, 30); Height = 0.30; Amp = 0.030; Speed = 0.55; Freq = 0.34; };
				{ Body = RGB(205, 38, 8); Crest = RGB(255, 150, 40); Height = 0.25; Amp = 0.034; Speed = -0.75; Freq = 0.40; };
				{ Body = RGB(255, 96, 12); Crest = RGB(255, 205, 80); Height = 0.19; Amp = 0.036; Speed = 0.95; Freq = 0.46; };
				{ Body = RGB(255, 150, 28); Crest = RGB(255, 246, 170); Height = 0.12; Amp = 0.032; Speed = -1.2; Freq = 0.55; };
			};
		});

		-- heat shimmer over the lava
		R:Gradient({
			Layer = 'Lighting'; Position = UDim2.fromScale(0, 0.45); Size = UDim2.fromScale(1, 0.55); Rotation = 90;
			Colors = Seq(RGB(255, 90, 10), RGB(255, 150, 30)); Transparency = NS(0, 1, 1, 0.5);
		});
		R:Glow({ Layer = 'Lighting'; Color = RGB(255, 120, 30); Size = 520; X = 0.5; Y = 1.0; Alpha = 0.955; Rings = 10; Pulse = { 1.8, 0.07 }; });

		R:Emitter({
			Shape = 'Ember'; Count = 36; Size = { 2, 5 }; Vx = { -0.012, 0.012 }; Vy = { -0.16, -0.06 };
			Alpha = { 0.05, 0.2 }; LifeFade = true; Wobble = { 0.012, 1.5, 3 };
			Colors = { RGB(255, 150, 40), RGB(255, 205, 80), RGB(255, 100, 30) };
		});
		R:Emitter({ -- fast bright sparks
			Shape = 'Circle'; Count = 16; Size = { 1, 2.5 }; Vx = { -0.03, 0.03 }; Vy = { -0.32, -0.18 };
			Alpha = { 0, 0.1 }; LifeFade = true; Colors = { RGB(255, 235, 150), RGB(255, 190, 80) };
		});
		R:Emitter({ -- ash falling
			Shape = 'Square'; Count = 14; Size = { 2, 4 }; Vx = { -0.01, 0.02 }; Vy = { 0.03, 0.07 }; Spin = { -60, 60 };
			Alpha = { 0.4, 0.75 }; Wobble = { 0.02, 0.6, 1.2 }; Colors = { RGB(70, 40, 36), RGB(110, 60, 40) };
		});
	end;

	-- a few flames licking out from BEHIND the bottom edge and two plumes behind each top corner: nothing covers the menu
	Accessory = function(A)
		local S = A.Scale;
		local W = A.Size.X;
		local N = math.max(4, math.floor(W / 130 + 0.5));

		for I = 0, N - 1 do
			local Wd, Ht = Roll({ 38, 50 }) * S, Roll({ 40, 54 }) * S;
			AccFlame(A, true, UDim2.new((I + 0.5) / N, Roll({ -12, 12 }), 1, 26), Wd, Ht, 0);
		end;

		for _, Side in ipairs({ 0, 1 }) do
			local Dir = Side == 0 and -1 or 1;
			for K = 0, 1 do
				AccFlame(A, true, UDim2.new(Side, Dir * (6 + K * 18), 0, 40), (40 - K * 8) * S, (70 - K * 14) * S, Dir * (8 + K * 8));
			end;
		end;

		AccDrift(A, { Count = 8; X = { 0, 1 }; Y = 1; OffY = 18; Dx = { -30, 30 }; Dy = { -44, -20 }; Size = { 3, 5 }; Colors = { RGB(255, 190, 80), RGB(255, 150, 40) }; Alpha = 0.05; Dur = { 2.2, 4.2 }; });
	end;
});

FX:RegisterScene({
	Name = 'Deep Sea'; Category = 'Nature'; Weight = 'Beautiful'; Transition = 'Ripple'; PanelAlpha = 0.3;
	Description = 'The abyss: a colossal kraken, glowing jellyfish, an anglerfish lure, marine snow and a passing whale';
	Build = function(R)
		R:Gradient({
			Layer = 'Base'; Rotation = 90; Drift = 0.1; DriftAmount = 0.08;
			Colors = Seq(RGB(8, 70, 96), RGB(4, 38, 66), RGB(2, 16, 34), RGB(1, 6, 14));
		});

		R:Rays({ Count = 5; Color = RGB(140, 255, 235); Width = { 40, 100 }; X = { 0.1, 0.9 }; Sway = 4; Start = 0.82; });
		R:Glow({ Layer = 'Atmosphere'; Color = RGB(120, 240, 230); Size = 560; X = 0.5; Y = -0.05; Alpha = 0.96; Rings = 10; Pulse = { 0.5, 0.07 }; });
		R:Caustics({ Layer = 'Atmosphere'; Count = 10; Depth = 0.35; Color = RGB(150, 255, 240); Alpha = 0.9; });

		R:Hero(HeroOf('Deep Sea'));
		R:Whale({ Layer = 'Decor'; Y = 0.5; Size = (R:Size().X) * 0.62; Color = RGB(2, 22, 42); Alpha = 0.45; Seconds = 95; });

		R:Jelly({ Layer = 'Decor'; Position = UDim2.fromScale(0.14, 0.2); Size = 70; Color = RGB(0, 255, 210); });
		R:Jelly({ Layer = 'Decor'; Position = UDim2.fromScale(0.84, 0.38); Size = 90; Color = RGB(120, 150, 255); });
		R:Jelly({ Layer = 'Decor'; Position = UDim2.fromScale(0.58, 0.58); Size = 54; Color = RGB(255, 120, 220); });

		-- an anglerfish lure far away: a small pulsing light
		R:Glow({ Layer = 'Decor'; Color = RGB(0, 255, 210); Size = 90; X = 0.3; Y = 0.7; Alpha = 0.9; Rings = 6; Pulse = { 2, 0.25 }; });

		R:Emitter({ -- marine snow
			Shape = 'Circle'; Count = 50; Size = { 1, 3 }; Vx = { -0.006, 0.006 }; Vy = { 0.012, 0.035 };
			Alpha = { 0.4, 0.8 }; Colors = { RGB(210, 255, 250) };
		});
		R:Emitter({ -- plankton
			Shape = 'Circle'; Count = 40; Size = { 1.5, 3.5 }; Vx = { -0.008, 0.008 }; Vy = { -0.012, 0.012 };
			Alpha = { 0.3, 0.8 }; Twinkle = 0.9; Colors = { RGB(0, 255, 210), RGB(90, 200, 255), RGB(150, 255, 160) };
		});
		R:Emitter({
			Shape = 'Bubble'; Count = 14; Size = { 4, 11 }; Vx = { -0.004, 0.004 }; Vy = { -0.1, -0.04 };
			Alpha = { 0.4, 0.8 }; Wobble = { 0.012, 1.2, 2.2 }; Colors = { RGB(200, 255, 250) };
		});
		R:Vignette({ Layer = 'Atmosphere'; Strength = 0.6; });
	end;

	-- kraken arms hugging the sides of the window, an anglerfish lure over the top edge, jellyfish peeking over it
	Accessory = function(A)
		local R, S = A.R, A.Scale;
		local Pal = { RGB(60, 255, 215), RGB(6, 50, 72), RGB(175, 255, 240), RGB(255, 90, 190) };
		local U = 100 * S;

		for I, C in ipairs({
			{ 'KrakenArm', UDim2.new(1, 0, 1, -66 * S), Vector2.new(0, 1.1) }, { 'KrakenArmL', UDim2.new(0, 0, 1, -66 * S), Vector2.new(0, 1.1) },
			{ 'KrakenArmT', UDim2.new(1, 0, 0, 66 * S), Vector2.new(0, -1.1) }, { 'KrakenArmTL', UDim2.new(0, 0, 0, 66 * S), Vector2.new(0, -1.1) },
		}) do
			local Pivot = A:Art(C[1], Pal, C[2], U, { Pivot = C[3]; });
			if Pivot then
				R:Sway(Pivot, { Rotation = { -2.4, 2.4 } }, 3 + I * 0.5, 'Decor');
			end;
		end;

		-- the lure: a stalk and a pulsing light
		local Stalk = A:Pivot(A.Front, UDim2.new(0.62, 0, 0, -6), 0);
		local Rod = R:New('Frame', { AnchorPoint = Vector2.new(0.5, 1); BackgroundColor3 = RGB(0, 255, 210); BackgroundTransparency = 0.3; Position = UDim2.fromOffset(0, 4); Size = UDim2.fromOffset(4, 46 * S); }, Stalk);
		R:New('UIGradient', { Rotation = 90; Transparency = NS(0, 0.6, 1, 0); }, Rod);
		R:Glow({ Layer = 'Decor'; Color = RGB(0, 255, 210); Size = 90 * S; X = 0.62; Y = -0.1; Alpha = 0.9; Rings = 6; Pulse = { 2, 0.2 }; });
		local Orb = R:New('Frame', { AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = RGB(190, 255, 245); Position = UDim2.fromOffset(0, -44 * S); Size = UDim2.fromOffset(20 * S, 20 * S); }, Stalk);
		Round(Orb, 0.5, 0);
		R:Sway(Orb, { BackgroundTransparency = { 0, 0.3 } }, 0.75, 'Decor');
		R:Sway(Stalk, { Rotation = { -6, 6 } }, 3.4, 'Decor');

		-- jellyfish bells over the top edge (the tentacles hang behind the window)
		A.BackR:Jelly({ Parent = A.Back; Position = UDim2.new(0.22, 0, 0, -8); Size = 50 * S; Color = RGB(0, 255, 210); });
		A.BackR:Jelly({ Parent = A.Back; Position = UDim2.new(0.8, 0, 0, -6); Size = 42 * S; Color = RGB(255, 120, 220); });
	end;
});

-- ---------------------------------------------------------------- tab transitions
-- Each function draws on the overlay layer above the tab area and returns its duration.
-- Full = false is the lighter variant used by the Balanced profile.
FX.Transitions.Fade = function()
	return 0;
end;

-- water: soft rings spread from the middle and a swell wipes up through the tab
FX.Transitions.Ripple = function(Layer, W, H, Full)
	local Size = math.min(W, H);

	for I = 1, 3 do
		local Ring = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromOffset(Size * 0.2, Size * 0.2); ZIndex = 13; Parent = Layer;
		});
		Round(Ring, 0.5, 0);

		local Stroke = Instance.new('UIStroke');
		Stroke.Color = RGB(205, 238, 255);
		Stroke.Thickness = 2;
		Stroke.Transparency = 0.6;
		Stroke.Parent = Ring;

		local Grow = Size * (0.7 + I * 0.3);
		Tw(Ring, { Size = UDim2.fromOffset(Grow, Grow) }, 0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, I * 0.06);
		Tw(Stroke, { Transparency = 1 }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.1 + I * 0.06);
		task.delay((0.8 + I * 0.06) * Library.AnimationSpeed, function()
			Ring:Destroy();
		end);
	end;

	if Full then
		local Wave = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0); BackgroundColor3 = RGB(60, 170, 220); BackgroundTransparency = 0.55; BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 1.05); Size = UDim2.fromScale(1.5, 0.9); ZIndex = 12; Parent = Layer;
		});
		Round(Wave, 0.5, 0);
		Tw(Wave, { Position = UDim2.fromScale(0.5, -0.95); BackgroundTransparency = 1; }, 0.62, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut);
	end;

	return 0.7;
end;

FX.Transitions.Light = function(Layer, W, H, Full)
	local Size = math.min(W, H);

	for I = 1, 5 do
		local Ring = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = RGB(255, 238, 190); BackgroundTransparency = 0.93; BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromOffset(Size * 0.3, Size * 0.3); ZIndex = 13; Parent = Layer;
		});
		Round(Ring, 0.5, 0);
		local Grow = Size * (0.9 + I * 0.28);
		Tw(Ring, { Size = UDim2.fromOffset(Grow, Grow); BackgroundTransparency = 1; }, 0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, I * 0.025);
	end;

	return 0.7;
end;

FX.Transitions.Scan = function(Layer, W, H, Full)
	local Cyan = RGB(0, 229, 255);

	local Bar = Library:Create('Frame', {
		BackgroundColor3 = Cyan; BorderSizePixel = 0; Position = UDim2.fromScale(0, -0.02); Size = UDim2.new(1, 0, 0, 2); ZIndex = 13; Parent = Layer;
	});
	local Trail = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0, 1); BackgroundColor3 = Cyan; BorderSizePixel = 0; Size = UDim2.new(1, 0, 0, 56); ZIndex = 13; Parent = Bar;
	});
	Library:Create('UIGradient', { Rotation = 90; Transparency = NS(0, 1, 1, 0.7); Parent = Trail; });

	Tw(Bar, { Position = UDim2.fromScale(0, 1.02) }, 0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut);

	if Full then -- a few glitch slices flash while the scan passes
		for I = 1, 4 do
			local Slice = Library:Create('Frame', {
				BackgroundColor3 = I % 2 == 0 and RGB(255, 43, 214) or Cyan; BackgroundTransparency = 1; BorderSizePixel = 0;
				Position = UDim2.new(FXRandom:NextNumber() * 0.4, 0, FXRandom:NextNumber() * 0.9, 0);
				Size = UDim2.new(0.25 + FXRandom:NextNumber() * 0.35, 0, 0, FXRandom:NextInteger(3, 8)); ZIndex = 13; Parent = Layer;
			});
			Tw(Slice, { BackgroundTransparency = 0.35 }, 0.02, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0.05 + I * 0.06);
			Tw(Slice, { BackgroundTransparency = 1 }, 0.07, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0.09 + I * 0.06);
		end;
	end;

	return 0.5;
end;

FX.Transitions.Warp = function(Layer, W, H, Full)
	local Count = Full and 18 or 10;
	local Reach = math.max(W, H) * 0.7;

	for I = 1, Count do
		local Pivot = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; BorderSizePixel = 0;
			Position = UDim2.fromScale(0.5, 0.5); Rotation = I * 360 / Count + FXRandom:NextNumber() * 8; Size = UDim2.fromOffset(0, 0);
			ZIndex = 13; Parent = Layer;
		});
		local Line = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0, 0.5); BackgroundColor3 = Color3.new(1, 1, 1); BackgroundTransparency = 0.1; BorderSizePixel = 0;
			Position = UDim2.fromOffset(12, 0); Size = UDim2.fromOffset(0, 2); ZIndex = 13; Parent = Pivot;
		});
		Library:Create('UIGradient', { Transparency = NS(0, 1, 1, 0); Parent = Line; });

		local Delay = FXRandom:NextNumber() * 0.08;
		Tw(Line, { Size = UDim2.fromOffset(Reach * (0.35 + FXRandom:NextNumber() * 0.4), 2); Position = UDim2.fromOffset(Reach * 0.3, 0); }, 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In, Delay);
		Tw(Line, { BackgroundTransparency = 1 }, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.3 + Delay);
	end;

	local Flash = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = RGB(190, 170, 255); BackgroundTransparency = 0.6; BorderSizePixel = 0;
		Position = UDim2.fromScale(0.5, 0.5); Size = UDim2.fromOffset(10, 10); ZIndex = 13; Parent = Layer;
	});
	Round(Flash, 0.5, 0);
	Tw(Flash, { Size = UDim2.fromOffset(Reach * 0.6, Reach * 0.6); BackgroundTransparency = 1; }, 0.45, Enum.EasingStyle.Quint);

	return 0.55;
end;

FX.Transitions.Petals = function(Layer, W, H, Full)
	for _ = 1, (Full and 14 or 8) do
		local Y = FXRandom:NextNumber();
		local Size = FXRandom:NextInteger(7, 12);
		local Petal = Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = FXRandom:NextNumber() < 0.5 and RGB(255, 170, 200) or RGB(255, 205, 222);
			BackgroundTransparency = 0.15; BorderSizePixel = 0; Position = UDim2.fromScale(-0.08, Y); Rotation = FXRandom:NextInteger(0, 180);
			Size = UDim2.fromOffset(Size * 1.7, Size); ZIndex = 13; Parent = Layer;
		});
		Round(Petal, 0.5, 0);

		local Delay = FXRandom:NextNumber() * 0.15;
		local Time = 0.5 + FXRandom:NextNumber() * 0.25;
		Tw(Petal, { Position = UDim2.fromScale(1.1, Y + (FXRandom:NextNumber() - 0.3) * 0.35); Rotation = Petal.Rotation + 300; }, Time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, Delay);
		Tw(Petal, { BackgroundTransparency = 1 }, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, Time - 0.1 + Delay);
	end;

	return 0.95;
end;

FX.Transitions.Flame = function(Layer, W, H, Full)
	local Wipe = Library:Create('Frame', {
		BackgroundColor3 = Color3.new(1, 1, 1); BorderSizePixel = 0; Position = UDim2.fromScale(0, 1); Size = UDim2.fromScale(1, 1); ZIndex = 13; Parent = Layer;
	});
	Library:Create('UIGradient', { Rotation = 90; Color = Seq(RGB(255, 190, 70), RGB(255, 90, 20)); Transparency = NS(0, 1, 0.5, 0.45, 1, 0.1); Parent = Wipe; });
	Tw(Wipe, { Position = UDim2.fromScale(0, -1) }, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut);

	if Full then
		for _ = 1, 10 do
			local X = FXRandom:NextNumber();
			local Ember = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0.5, 0.5); BackgroundColor3 = RGB(255, 170, 60); BackgroundTransparency = 0.2; BorderSizePixel = 0;
				Position = UDim2.fromScale(X, 1.05); Size = UDim2.fromOffset(4, 4); ZIndex = 13; Parent = Layer;
			});
			Round(Ember, 0.5, 0);
			local Delay = FXRandom:NextNumber() * 0.15;
			Tw(Ember, { Position = UDim2.fromScale(X + (FXRandom:NextNumber() - 0.5) * 0.2, -0.05); BackgroundTransparency = 1; }, 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, Delay);
		end;
	end;

	return 0.65;
end;


-- Plays the active scene's transition over the tab area. Purely decorative: the overlay never takes input,
-- a new transition clears the old one, and nothing here waits on the tab switch itself.
function FX:PlayTransition()
	local S = FX.Settings;
	local Profile = FX.Profiles[S.Performance];
	local Layer = FX.TransLayer;

	if not (S.Transitions and S.Animations and Layer and Profile and Profile.Transition ~= 'none') then
		return;
	end;

	local Scene = FX.Scene;
	local Play = Scene and FX.Transitions[Scene.Transition or 'Fade'];
	if not Play then
		return;
	end;

	FX.TransToken = FX.TransToken + 1;
	local Token = FX.TransToken;
	Layer:ClearAllChildren();

	local Size = Layer.AbsoluteSize;
	local Full = Profile.Transition == 'full';

	if Full then -- quick tint behind the effect so the content swap reads as one move
		local Veil = Library:Create('Frame', {
			BackgroundColor3 = Library.BackgroundColor; BackgroundTransparency = 1; BorderSizePixel = 0;
			Size = UDim2.fromScale(1, 1); ZIndex = 11; Parent = Layer;
		});
		Tw(Veil, { BackgroundTransparency = 0.45 }, 0.1, Enum.EasingStyle.Quad);
		Tw(Veil, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.14);
	end;

	local Ok, Duration = pcall(Play, Layer, Size.X, Size.Y, Full);
	if not Ok then
		warn('[Library.FX] transition failed: ' .. tostring(Duration));
		Layer:ClearAllChildren();
		return;
	end;

	task.delay(math.max(Duration or 0, 0.5) * Library.AnimationSpeed + 0.1, function()
		if FX.TransToken == Token then
			Layer:ClearAllChildren();
		end;
	end);
end;

-- ===== Username privacy =====
-- Anything that shows the player's name registers here, so one toggle hides it everywhere it is drawn.
Library.ShowName = true;
Library.PrivateItems = {};
Library.ShowNameListeners = {};

function Library:RegisterPrivate(Label, Show, Hide)
	table.insert(Library.PrivateItems, { Inst = Label; Show = Show; Hide = Hide; });
	Label.Text = Library.ShowName and Show or Hide;
end;

function Library:OnShowNameChanged(Fn)
	table.insert(Library.ShowNameListeners, Fn);
	Fn(Library.ShowName);
end;

function Library:SetShowName(Bool)
	Library.ShowName = Bool ~= false;

	for _, Item in ipairs(Library.PrivateItems) do
		if Item.Inst.Parent then
			Item.Inst.Text = Library.ShowName and Item.Show or Item.Hide;
		end;
	end;

	for _, Fn in ipairs(Library.ShowNameListeners) do
		pcall(Fn, Library.ShowName);
	end;
end;

-- ===== Live graphs (one shared sampler for every AddGraph) =====
Library.Graphs = {};

function Library:_EnsureGraphTicker()
	if Library.GraphTicker then
		return;
	end;
	Library.GraphTicker = true;

	Library:GiveSignal(RunService.Heartbeat:Connect(function(Dt)
		if not Library.Toggled then
			return;
		end;

		for _, G in ipairs(Library.Graphs) do
			G.Elapsed = G.Elapsed + Dt;

			if G.Elapsed >= G.Interval and G.Plot.Parent then
				G.Elapsed = 0;
				local Ok, Value = pcall(G.Sample);
				if Ok and type(Value) == 'number' then
					G:Push(Value);
				end;
			end;
		end;
	end));
end;
function Library:CreateWindow(...)
	local Arguments = { ... }
	local Config = { AnchorPoint = Vector2.zero }

	if type(...) == 'table' then
		Config = ...;
	else
		Config.Title = Arguments[1]
		Config.AutoShow = Arguments[2] or false;
	end

	if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
	if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 1 end
	if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.4 end
	if type(Config.ShowCustomCursor) ~= 'boolean' then Library.ShowCustomCursor = true else Library.ShowCustomCursor = Config.ShowCustomCursor end

	if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
	if typeof(Config.Size) ~= 'UDim2' then 
		Config.Size = UDim2.fromOffset(740, 540)
		if Library.IsMobile then
			-- a phone: 640 wide, but never wider than the screen (small phones), as tall as the screen allows
			local Viewport = workspace.CurrentCamera.ViewportSize;
			local MobileWidth = math.floor(math.clamp(Viewport.X - 24, 420, 640));
			local ViewportSizeYOffset = tonumber(Viewport.Y) - 35;
			if ViewportSizeYOffset >= 200 and ViewportSizeYOffset <= 600 then
				Config.Size = UDim2.fromOffset(MobileWidth, ViewportSizeYOffset)
			else
				Config.Size = UDim2.fromOffset(MobileWidth, 350)
			end
		end
	end

	if Config.Resizable == nil then Config.Resizable = true end -- drag the bottom-right corner to resize

	if Config.TabPadding <= 0 then
		Config.TabPadding = 1
	end

	if Config.Center then
		-- Config.AnchorPoint = Vector2.new(0.5, 0.5)
		Config.Position = UDim2.new(0.5, -Config.Size.X.Offset/2, 0.5, -Config.Size.Y.Offset/2)
	end
	
	local SidebarWidth = type(Config.SidebarWidth) == 'number' and Config.SidebarWidth or (Library.IsMobile and 124 or 140);
	local HeaderHeight = 36;

	local Outer = Library:Create('Frame', {
		AnchorPoint = Config.AnchorPoint;
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = Config.Position;
		Size = Config.Size;
		Visible = false;
		ZIndex = 1;
		Parent = ScreenGui;
	});

	LibraryMainOuterFrame = Outer;
	Library:MakeDraggable(Outer, HeaderHeight);

	-- Body scales around the window center for the open / close pop
	local Body = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0.5, 0.5);
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = UDim2.fromScale(0.5, 0.5);
		Size = UDim2.fromScale(1, 1);
		ZIndex = 1;
		Parent = Outer;
	});

	local BodyScale = Library:Create('UIScale', {
		Parent = Body;
	});

	local Shadow = Library:AddShadow(Body, 34, 0.35);

	-- no drop shadow around the window unless asked for (Config.Shadow = true or Library.Shadows = true).
	-- Glow Mode still draws its accent glow with this same frame while it is switched on.
	local ShadowEnabled = Config.Shadow
	if ShadowEnabled == nil then
		ShadowEnabled = Library.Shadows
	end
	Shadow.Visible = ShadowEnabled == true;
	local ShadowTransparency = Shadow.ImageTransparency;

	-- everything inside the window lives in one CanvasGroup -> a single property fades the whole thing
	local Inner = Library:CreateCanvas({
		BackgroundColor3 = Library.BackgroundColor;
		BorderSizePixel = 0;
		Size = UDim2.fromScale(1, 1);
		ZIndex = 1;
		Parent = Body;
	});

	Library:AddCorner(Inner, 8);
	Library:AddToRegistry(Inner, { BackgroundColor3 = 'BackgroundColor'; });

	-- Theme FX sits behind everything in the window (first child, so it is drawn first).
	-- If anything in the effects engine fails, the menu itself keeps working without it.
	local FXHolder = Library:Create('Frame', {
		Name = 'FXHolder';
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Size = UDim2.fromScale(1, 1);
		ZIndex = 1;
		Parent = Inner;
	});

	do
		local Ok, Err = pcall(function()
			FX.Main = FX:CreateRenderer(FXHolder, {
				ZIndex = 1;
				SizeFrom = Outer;
				Visible = function() return Outer.Visible; end;
				OnApply = function() FX:ApplyPanels(); end;
			});

			-- scenes that use pixel geometry (Cyber grid) are rebuilt once the window stops being resized
			Outer:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
				if FX.Scene and FX.Scene.Pixel then
					FX:QueueRebuild(0.35);
				end;
			end);

			FX.Main:SetScene(FX.Scene);
		end);

		if not Ok then
			FX.Main = nil;
			warn('[Library.FX] disabled: ' .. tostring(Err));
		end;
	end;

	if Config.Resizable then
		Library:MakeResizable(Outer, Library.MinSize, Inner);
	end

	-- The border sits outside the canvas so its animated gradient doesn't make the whole window re-render
	local Border = Library:Create('Frame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Size = UDim2.fromScale(1, 1);
		ZIndex = 2; -- above the canvas, below popups (dropdowns / pickers start at 14)
		Parent = Body;
	});

	Library:AddCorner(Border, 8);

	local InnerStroke = Library:Create('UIStroke', {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
		Color = Color3.new(1, 1, 1);
		LineJoinMode = Enum.LineJoinMode.Round;
		Thickness = 1;
		Parent = Border;
	});

	local function BorderColors()
		if Library.RGBBorder then -- UI-only "RGB Border" mode: a full hue wheel around the frame
			local Keys = {};
			for I = 0, 5 do
				Keys[#Keys + 1] = ColorSequenceKeypoint.new(I / 5, Color3.fromHSV(I / 5, 0.75, 1));
			end;
			return ColorSequence.new(Keys);
		end;

		local Base = Library.BorderColor:Lerp(Library.AccentColor, 0.3);

		if not Library.AnimatedBorder then
			return ColorSequence.new(Base);
		end;

		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, Base),
			ColorSequenceKeypoint.new(0.36, Base),
			ColorSequenceKeypoint.new(0.5, Library.AccentColor),
			ColorSequenceKeypoint.new(0.64, Base),
			ColorSequenceKeypoint.new(1, Base),
		});
	end;

	local BorderGradient = Library:Create('UIGradient', {
		Color = BorderColors();
		Parent = InnerStroke;
	});

	Library:AddToRegistry(BorderGradient, { Color = BorderColors; });

	-- slow light sweep around the border (~9s per lap)
	Library:GiveSignal(RenderStepped:Connect(function(Delta)
		if Outer.Visible and (Library.AnimatedBorder or Library.RGBBorder) then
			BorderGradient.Rotation = (BorderGradient.Rotation + Delta * (Library.RGBBorder and 110 or 40)) % 360;
		end;
	end));

	-- ===== Glow Mode / Cinematic Mode =====
	-- UI-only looks: they change how this window is drawn and nothing else.
	Library.GlowMode = false;
	Library.Cinematic = false;
	Library.RGBBorder = false;
	Library.GlowStrength = 2; -- 1 (soft) .. 3 (strong)
	Library.GlowParts = { Shadow = true; Border = true; };

	local function GlowShadowOn()
		return Library.GlowMode and (Library.GlowParts == nil or Library.GlowParts.Shadow == true);
	end;

	Library:AddToRegistry(Shadow, { ImageColor3 = function() return GlowShadowOn() and Library.AccentColor or Library.Black; end; });

	local GlowTween, GlowToken = nil, 0;

	local function StopGlow()
		GlowToken = GlowToken + 1;
		if GlowTween then
			GlowTween:Cancel();
			GlowTween = nil;
		end;
	end;

	local function StartGlow() -- accent-colored shadow that breathes + a thicker border
		StopGlow();
		Shadow.Visible = (ShadowEnabled == true) or GlowShadowOn();
		local Token = GlowToken;

		local Parts = Library.GlowParts or {};
		Shadow.ImageColor3 = GlowShadowOn() and Library.AccentColor or Library.Black;
		Library:Tween(InnerStroke, { Thickness = (Library.GlowMode and Parts.Border) and 2 or 1 }, 0.4);

		if not GlowShadowOn() then
			Library:Tween(Shadow, { ImageTransparency = ShadowTransparency }, 0.4);
			return;
		end;

		Library:Tween(Shadow, { ImageTransparency = 0.5 }, 0.4);

		task.delay(0.45 * Library.AnimationSpeed, function()
			if Token ~= GlowToken or not Library.GlowMode or not Outer.Visible then
				return;
			end;

			GlowTween = TweenService:Create(Shadow, TweenInfo.new(1.2 * Library.AnimationSpeed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = math.clamp(0.42 - 0.12 * Library.GlowStrength, 0.02, 0.4) });
			GlowTween:Play();
		end);
	end;

	-- darkened edges over the window (+ slower effect motion, see FX.TimeScale)
	local CineHolder = Library:Create('Frame', {
		BackgroundTransparency = 1; BorderSizePixel = 0; Size = UDim2.fromScale(1, 1); Visible = false; ZIndex = 10; Parent = Inner;
	});
	local CineEdges = {};

	for _, E in ipairs({
		{ Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 0.3), 90 };
		{ Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.fromScale(1, 0.3), 270 };
		{ Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.fromScale(0.22, 1), 0 };
		{ Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.fromScale(0.22, 1), 180 };
	}) do
		local F = Library:Create('Frame', {
			AnchorPoint = E[1]; BackgroundColor3 = Color3.new(0, 0, 0); BackgroundTransparency = 1; BorderSizePixel = 0;
			Position = E[2]; Size = E[3]; ZIndex = 10; Parent = CineHolder;
		});
		Library:Create('UIGradient', {
			Rotation = E[4];
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) });
			Parent = F;
		});
		table.insert(CineEdges, F);
	end;

	-- ===== Accessories =====
	-- Ornaments around the OUTSIDE of the window that belong to the theme (Heaven: curved wings that swing with the window and a fairy,
	-- Deep Sea: kraken arms, Vanguard: a crest of blades ...). They never cover the controls: pieces behind the window (AccBack) only
	-- show outside it, the others (AccFront) sit over the edge. Art comes from the same figure lists the store preview draws, as
	-- CanvasGroups: drawn once, afterwards they are only moved, so they cost almost nothing per frame.
	-- Config.Accessories = false turns them off (phones start without them), Config.AccessorySize = size in px (default 60% of the window height).
	-- Config.Wings / Config.WingSize still work (older scripts).
	local AccDefault = Config.Accessories;
	if AccDefault == nil then
		AccDefault = Config.Wings;
	end;
	if AccDefault == nil then
		AccDefault = not Library.IsMobile;
	end;

	local AccNormal = math.floor(Config.Size.Y.Offset * 0.6); -- the size that means "normal" for Window:SetAccessorySize
	local AccSizeConfig = type(Config.AccessorySize) == 'number' and Config.AccessorySize or (type(Config.WingSize) == 'number' and Config.WingSize or AccNormal);

	local Accessories = {
		Enabled = AccDefault == true;
		Scale = math.clamp(AccSizeConfig / AccNormal, 0.6, 1.3);
		Pieces = {}; Springs = {};
		Size = Vector2.new(Config.Size.X.Offset, Config.Size.Y.Offset);
	};

	local AccAlpha = Instance.new('NumberValue'); -- 0 = invisible, 1 = visible (fades with the window)
	AccAlpha.Value = 0;

	local AccBack = Library:Create('Frame', {
		Name = 'AccessoriesBack'; BackgroundTransparency = 1; BorderSizePixel = 0; Size = UDim2.fromScale(1, 1);
		Visible = false; ZIndex = 0; Parent = Body;
	});

	local AccFront = Library:Create('Frame', {
		Name = 'AccessoriesFront'; BackgroundTransparency = 1; BorderSizePixel = 0; Size = UDim2.fromScale(1, 1);
		Visible = false; ZIndex = 4; Parent = Body;
	});

	local AccR, AccBackR;

	do
		local Ok, Err = pcall(function()
			AccR = FX:CreateRenderer(AccFront, {
				ZIndex = 4; SizeFrom = Outer; NoClip = true;
				Visible = function() return Outer.Visible and Accessories.Enabled; end;
				OnApply = function(R) AccBack.Visible = Accessories.Enabled and R.E.Decor == true; end;
			});

			-- same renderer, but everything it makes lies BEHIND the window (ZIndex 0) inside AccBack
			AccBackR = setmetatable({
				Z = 0; Layers = { Base = AccBack; Atmosphere = AccBack; Decor = AccBack; Particles = AccBack; Lighting = AccBack; };
			}, { __index = AccR });
		end);

		if not Ok then
			AccR = nil;
			warn('[Library.FX] accessories disabled: ' .. tostring(Err));
		end;
	end;

	Accessories.R = AccR;
	Accessories.BackR = AccBackR;
	Accessories.Back = AccBack;
	Accessories.Front = AccR and AccR.Layers.Decor or AccFront;

	local function IsGroupGui(Gui)
		return Gui:IsA('CanvasGroup');
	end;

	-- a zero sized frame: rotating it swings everything inside around its position
	function Accessories:Pivot(Parent, Position, Rotation)
		return Library:Create('Frame', {
			AnchorPoint = Vector2.new(0.5, 0.5); BackgroundTransparency = 1; BorderSizePixel = 0;
			Position = Position; Rotation = Rotation or 0; Size = UDim2.fromOffset(0, 0); Parent = Parent;
		});
	end;

	-- a CanvasGroup piece that fades with the window. Back = behind the window
	function Accessories:Canvas(Parent, Props, Back)
		local R = Back and AccBackR or AccR;
		local Piece = MakeCanvas(R, Props, Parent);

		if IsGroupGui(Piece) then
			Piece.GroupTransparency = 1 - AccAlpha.Value;
			table.insert(Accessories.Pieces, Piece);
		end;

		return Piece;
	end;

	-- Draws a piece of figure art (Name from Figures). Where = a UDim2 for the figure's centre, Unit = px per figure unit.
	-- Opts: Pal (4 colours), Back, View { x, y, w, h } (the part of the figure box to draw), Pivot (Vector2 in figure units: the point it swings around)
	-- Returns the pivot frame (rotate it / give it a spring) and the piece.
	function Accessories:Art(Name, Pal, Where, Unit, Opts)
		Opts = Opts or {};
		local Cmds = DecodeFigure(Name);
		local IsEmblem = false;
		if not Cmds and Emblems[Name] then
			Cmds, IsEmblem = Emblems[Name](), true;
		end;

		if not (Cmds and AccR) then
			return nil;
		end;

		local View = Opts.View or (IsEmblem and { -1.2, -1.2, 2.4, 2.4 } or { -1.1, -1.1, 2.2, 2.2 });
		local W, H = math.ceil(View[3] * Unit), math.ceil(View[4] * Unit);
		local OX, OY = -View[1] * Unit, -View[2] * Unit;
		local P = Opts.Pivot or Vector2.new(0, 0);
		local R = Opts.Back and AccBackR or AccR;
		local Parent = Opts.Back and AccBack or AccR.Layers.Decor;

		local Pivot = Accessories:Pivot(Parent, UDim2.new(Where.X.Scale, Where.X.Offset + P.X * Unit, Where.Y.Scale, Where.Y.Offset + P.Y * Unit), 0);
		local Piece = Accessories:Canvas(Pivot, {
			Position = UDim2.fromOffset(-P.X * Unit - OX, -P.Y * Unit - OY); Size = UDim2.fromOffset(W, H);
		}, Opts.Back);

		DrawArt(function(Class, Props, Par) return R:New(Class, Props, Par); end, Piece, Cmds, OX, OY, Unit, Pal, IsGroupGui(Piece) and 1 or AccAlpha.Value);
		return Pivot, Piece;
	end;

	-- a piece that swings like something hanging from the window: a spring on the pivot's rotation. The window's speed and
	-- acceleration push it (see the loop below), IdleAmp is a gentle sway when everything is still.
	-- O: Side (1 / -1: which way vertical movement turns it), GX / GY (how strongly it follows horizontal / vertical movement),
	--    K (stiffness), C (damping), Max (degrees), IdleAmp, IdleSpeed, Base (degrees it rests at)
	function Accessories:Spring(Pivot, O)
		O = O or {};
		table.insert(Accessories.Springs, {
			Pivot = Pivot; Base = O.Base or Pivot.Rotation; A = 0; V = 0; Side = O.Side or 1; GX = O.GX or 1; GY = O.GY or 1;
			K = O.K or 60; C = O.C or 4.5; Max = O.Max or 46; IdleAmp = O.IdleAmp or 0; IdleSpeed = O.IdleSpeed or 1.2;
			Phase = FXRandom:NextNumber() * 6.28;
		});
	end;

-- [[rig:acckick]]
	-- ---- what hangs from the window reacts to a kick (a tab change = Power 1, a pressed control = less)
	Accessories.KickFns = {};

	-- little effects at a point of the window (px from its top-left corner), behind the window: only what flies outside the edge shows
	-- Kind: spark streak ring petal bubble
	function Accessories:Burst(Kind, X, Y, Color, N, Power)
		if not AccBackR then
			return;
		end;

		AccBackR:Burst(AccBack, { Color, Color, Color, Color }, {
			Kind = Kind; X = X / 100; Y = Y / 100; Slot = 1; N = N or 6; Power = Power or 1; Unit = 100; Cx = 0; Cy = 0; Layer = 'Decor';
		});
	end;

	-- a scene's accessory builder can ask for its own effect: A:OnKick(function(Power) ... end)
	function Accessories:OnKick(Fn)
		table.insert(Accessories.KickFns, Fn);
	end;

	-- where each scene's sparks come from (the same places as the store preview)
	local AccKicks = {
		Heaven = function(P, W, H) local C = RGB(255, 252, 236); Accessories:Burst('spark', W / 2, -44, RGB(255, 225, 130), 7, P); Accessories:Burst('spark', 34, -40, RGB(255, 236, 170), 5, P); Accessories:Burst('petal', 48, H + 8, C, 5, P); Accessories:Burst('petal', W - 52, H + 10, C, 5, P); end;
		Inferno = function(P, W, H) for _ = 1, 3 do Accessories:Burst('spark', (0.1 + FXRandom:NextNumber() * 0.8) * W, H + 6, RGB(255, 170, 60), 5, P); end; Accessories:Burst('spark', 0, H, RGB(255, 120, 30), 4, P); Accessories:Burst('spark', W, H, RGB(255, 120, 30), 4, P); end;
		Ocean = function(P, W, H) local C = RGB(210, 245, 255); Accessories:Burst('bubble', W - 4, H, C, 5, P); Accessories:Burst('bubble', 4, H, C, 4, P); Accessories:Burst('ring', W / 2, -10, RGB(170, 232, 255), 1, P); end;
		Sakura = function(P, W, H) local C = RGB(255, 185, 210); Accessories:Burst('petal', 16, -40, C, 6, P); Accessories:Burst('petal', W - 16, -40, C, 6, P); Accessories:Burst('spark', W / 2, -30, RGB(255, 236, 170), 5, P); end;
		Void = function(P, W, H) local C = RGB(190, 170, 255); Accessories:Burst('spark', W / 2, -22, RGB(170, 150, 255), 8, P); Accessories:Burst('streak', 0, H * 0.55, C, 3, P); Accessories:Burst('streak', W, H * 0.62, C, 3, P); end;
		Vanguard = function(P, W, H) local C = RGB(255, 190, 180); Accessories:Burst('spark', -2, -46, RGB(255, 110, 100), 8, P); Accessories:Burst('spark', W + 2, -46, RGB(255, 110, 100), 8, P); Accessories:Burst('streak', 0, H * 0.4, C, 3, P); Accessories:Burst('streak', W, H * 0.4, C, 3, P); end;
		['Deep Sea'] = function(P, W, H) local C = RGB(175, 255, 240); Accessories:Burst('bubble', 4, H - 60, C, 5, P); Accessories:Burst('bubble', W - 4, H - 60, C, 5, P); Accessories:Burst('spark', W * 0.62, -62, RGB(0, 255, 210), 5, P); end;
	};

	function Accessories:Kick(Power)
		for _, S in ipairs(Accessories.Springs) do
			S.V = S.V + S.Side * Power * 34 * (0.7 + FXRandom:NextNumber() * 0.6);
		end;

		if not (Accessories.Enabled and Outer.Visible and AccR and AccR.E and AccR.E.Particles) then
			return;
		end;

		local W, H = Accessories.Size.X, Accessories.Size.Y;
		local Own = AccKicks[FX.SceneName];
		if Own then
			local Ok, Err = pcall(Own, Power, W, H);
			if not Ok then
				warn('[Library.FX] accessory kick failed: ' .. tostring(Err));
			end;
		end;

		for _, Fn in ipairs(Accessories.KickFns) do
			pcall(Fn, Power);
		end;
	end;
-- [[/rig:acckick]]
	local AccScene = {
		Name = 'Accessories';
		Build = function(R)
			AccBack:ClearAllChildren();
			table.clear(Accessories.Pieces);
			table.clear(Accessories.Springs);
			table.clear(Accessories.KickFns);
			Accessories.Size = Vector2.new(Outer.AbsoluteSize.X > 50 and Outer.AbsoluteSize.X or Config.Size.X.Offset, Outer.AbsoluteSize.Y > 50 and Outer.AbsoluteSize.Y or Config.Size.Y.Offset);

			local Scene = FX.Scene;
			if Accessories.Enabled and Scene and Scene.Accessory then
				Scene.Accessory(Accessories, R);
			end;
		end;
	};

	function Accessories:Rebuild()
		if AccR then
			AccR:SetScene(AccScene);
		end;
	end;

	function Accessories:Show(On)
		AccFront.Visible = On;
		AccBack.Visible = On and (AccR == nil or AccR.E == nil or AccR.E.Decor == true);
	end;

	-- fades with the window (same time, style and direction as Library.Toggle)
	AccAlpha:GetPropertyChangedSignal('Value'):Connect(function()
		local Group = 1 - AccAlpha.Value;
		for _, Piece in ipairs(Accessories.Pieces) do
			if Piece.Parent then
				Piece.GroupTransparency = Group;
			end;
		end;
	end);

	function Accessories:Open(Time)
		if not Accessories.Enabled then return end;
		Accessories:Show(true);
		Library:Tween(AccAlpha, { Value = 1 }, Time or 0.4);
	end;

	function Accessories:Close(Time)
		Library:Tween(AccAlpha, { Value = 0 }, Time or 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
	end;

	function Accessories:Reset()
		Library:SetNow(AccAlpha, 'Value', 0);
	end;

	-- the physics: the window's own movement (it is dragged by its header) swings whatever has a spring
	local AccClock, AccPending = 0, 0;
	local AccFrameTime = 1 / (Library.IsMobile and 30 or 45);
	local AccLastPos = Vector2.new(0, 0);
	local AccVel = Vector2.new(0, 0);
	local AccAccel = Vector2.new(0, 0);

	Library:GiveSignal(RenderStepped:Connect(function(Delta)
		local Shown = Outer.Visible and Accessories.Enabled;

		if AccFront.Visible ~= Shown and (Shown or AccAlpha.Value <= 0.01) then
			Accessories:Show(Shown);
		end;

		if not Shown or #Accessories.Springs == 0 then
			AccLastPos = Outer.AbsolutePosition;
			return;
		end;

		AccPending = AccPending + Delta;
		if AccPending < AccFrameTime then
			return;
		end;

		local Step = AccPending;
		AccPending = 0;
		AccClock = AccClock + Step;

		local Pos = Outer.AbsolutePosition;
		local NewVel = (Pos - AccLastPos) / Step;
		AccLastPos = Pos;

		local Smooth = AccVel:Lerp(NewVel, 0.5); -- the window jumps with the mouse: smooth the speed a little
		AccAccel = (Smooth - AccVel) / Step;
		AccVel = Smooth;

		local SX = AccVel.X * 0.024 + AccAccel.X * 0.0012;
		local SY = AccVel.Y * 0.024 + AccAccel.Y * 0.0012;
		local Dt = math.min(Step, 0.05);

		for _, S in ipairs(Accessories.Springs) do
			if S.Pivot.Parent then
				local Target = math.clamp(-S.GX * SX - S.Side * S.GY * SY, -S.Max, S.Max);
				S.V = S.V + (S.K * (Target - S.A) - S.C * S.V) * Dt;
				S.A = S.A + S.V * Dt;

				local Idle = S.IdleAmp > 0 and math.sin(AccClock * S.IdleSpeed + S.Phase) * S.IdleAmp or 0;
				S.Pivot.Rotation = S.Base + S.A + Idle;
			end;
		end;
	end));

	local Wings = Accessories; -- Library:Toggle uses the old name

	-- Header (back arrow, breadcrumbs, search)
	local Header = Library:Create('Frame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Size = UDim2.new(1, 0, 0, HeaderHeight - 1);
		ZIndex = 2;
		Parent = Inner;
	});

	local HeaderLine = Library:Create('Frame', {
		BackgroundColor3 = Library.BorderColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 0, 0, HeaderHeight - 1);
		Size = UDim2.new(1, 0, 0, 1);
		ZIndex = 2;
		Parent = Inner;
	});
	Library:AddToRegistry(HeaderLine, { BackgroundColor3 = 'BorderColor'; });

	-- accent glint on the header line, under the sidebar
	local HeaderGlow = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 0, 0, HeaderHeight - 1);
		Size = UDim2.new(0, SidebarWidth * 2, 0, 1);
		ZIndex = 3;
		Parent = Inner;
	});
	Library:AddToRegistry(HeaderGlow, { BackgroundColor3 = 'AccentColor'; });
	Library:Create('UIGradient', {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		});
		Parent = HeaderGlow;
	});

	local BackButton = Library:CreateLabel({
		AnchorPoint = Vector2.new(0, 0.5);
		BackgroundColor3 = Library.MainColor;
		BackgroundTransparency = 1;
		Position = UDim2.new(0, 8, 0.5, 0);
		Size = UDim2.new(0, 22, 0, 22);
		Font = Library.FontBold;
		Text = '<';
		TextSize = 14;
		ZIndex = 3;
		Parent = Header;
	});

	Library:AddCorner(BackButton, 6);
	Library:AddToRegistry(BackButton, { BackgroundColor3 = 'MainColor'; TextColor3 = 'FontColor'; });

	BackButton.MouseEnter:Connect(function()
		Library:Tween(BackButton, { BackgroundTransparency = 0 }, 0.2);
	end);

	BackButton.MouseLeave:Connect(function()
		Library:Tween(BackButton, { BackgroundTransparency = 1 }, 0.3);
	end);

	Library:OnTap(BackButton, function(Input)
		do
			task.spawn(Library.Toggle);
		end;
	end);

	local Crumbs = Library:Create('Frame', {
		BackgroundTransparency = 1;
		Position = UDim2.new(0, 34, 0, 0);
		Size = UDim2.new(1, -250, 1, 0);
		ZIndex = 3;
		Parent = Header;
	});

	Library:Create('UIListLayout', {
		FillDirection = Enum.FillDirection.Horizontal;
		SortOrder = Enum.SortOrder.LayoutOrder;
		VerticalAlignment = Enum.VerticalAlignment.Center;
		Parent = Crumbs;
	});

	local Window = {
		Tabs = {};
		Crumbs = {};
	};

	local CrumbObjects = {};

	local function BuildCrumbs(Title)
		for _, Obj in next, CrumbObjects do
			Library:RemoveFromRegistry(Obj);
			Obj:Destroy();
		end;
		CrumbObjects = {};

		local Parts = {};
		for Part in string.gmatch(Title, '[^|]+') do
			local Trimmed = Part:match('^%s*(.-)%s*$');
			if #Trimmed > 0 then
				table.insert(Parts, Trimmed);
			end;
		end;
		if #Parts == 0 then
			Parts[1] = Title;
		end;
		Window.Crumbs = Parts;

		for Idx, Part in ipairs(Parts) do
			if Idx > 1 then
				local Sep = Library:Create('Frame', {
					BackgroundColor3 = Library.BorderColor;
					BorderSizePixel = 0;
					Size = UDim2.new(0, 1, 0, 14);
					LayoutOrder = Idx * 2 - 1;
					ZIndex = 3;
					Parent = Crumbs;
				});
				Library:AddToRegistry(Sep, { BackgroundColor3 = 'BorderColor'; });
				table.insert(CrumbObjects, Sep);
			end;

			local CrumbLabel = Library:CreateLabel({
				AutomaticSize = Enum.AutomaticSize.X;
				Size = UDim2.new(0, 0, 1, 0);
				Font = Idx == 1 and Library.FontBold or Library.Font;
				Text = Part;
				TextSize = 13;
				LayoutOrder = Idx * 2;
				ZIndex = 3;
				Parent = Crumbs;
			});

			if Idx > 1 then
				CrumbLabel.TextColor3 = Library.DimFontColor;
				Library.RegistryMap[CrumbLabel].Properties.TextColor3 = 'DimFontColor';
			end;

			Library:Create('UIPadding', {
				PaddingLeft = UDim.new(0, 8);
				PaddingRight = UDim.new(0, 8);
				Parent = CrumbLabel;
			});
			table.insert(CrumbObjects, CrumbLabel);
		end;
	end;

	BuildCrumbs(Config.Title or '');

	-- search pill: widens a bit while focused
	local SearchOuter = Library:Create('Frame', {
		AnchorPoint = Vector2.new(1, 0.5);
		BackgroundColor3 = Library.MainColor;
		BorderSizePixel = 0;
		Position = UDim2.new(1, -10, 0.5, 0);
		Size = UDim2.new(0, 170, 0, 22);
		ZIndex = 3;
		Parent = Header;
	});

	Library:AddCorner(SearchOuter, 11);
	local SearchStroke = Library:AddStroke(SearchOuter, 'BorderColor');

	Library:AddToRegistry(SearchOuter, {
		BackgroundColor3 = 'MainColor';
	});

	local SearchBox = Library:Create('TextBox', {
		BackgroundTransparency = 1;
		Position = UDim2.new(0, 12, 0, 0);
		Size = UDim2.new(1, -24, 1, 0);
		Font = Library.Font;
		PlaceholderText = 'Search...';
		PlaceholderColor3 = Library.DimFontColor;
		Text = '';
		TextColor3 = Library.FontColor;
		TextSize = 12;
		TextXAlignment = Enum.TextXAlignment.Left;
		ClearTextOnFocus = false;
		ZIndex = 4;
		Parent = SearchOuter;
	});
	Library:AddToRegistry(SearchBox, {
		TextColor3 = 'FontColor';
		PlaceholderColor3 = 'DimFontColor';
	});

	SearchBox.Focused:Connect(function()
		Library.RegistryMap[SearchStroke].Properties.Color = 'AccentColor';
		Library:Tween(SearchStroke, { Color = Library.AccentColor }, 0.25);
		Library:Tween(SearchOuter, { Size = UDim2.new(0, 210, 0, 22) }, 0.4);
	end);

	SearchBox.FocusLost:Connect(function()
		Library.RegistryMap[SearchStroke].Properties.Color = 'BorderColor';
		Library:Tween(SearchStroke, { Color = Library.BorderColor }, 0.35);
		if SearchBox.Text == '' then
			Library:Tween(SearchOuter, { Size = UDim2.new(0, 170, 0, 22) }, 0.4);
		end;
	end);

	-- Sidebar (tab list + footer)
	local Sidebar = Library:Create('Frame', {
		BackgroundColor3 = Library.MainColor;
		BackgroundTransparency = 0.55;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 0, 0, HeaderHeight);
		Size = UDim2.new(0, SidebarWidth, 1, -HeaderHeight);
		ZIndex = 2;
		Parent = Inner;
	});
	Library:AddToRegistry(Sidebar, { BackgroundColor3 = 'MainColor'; });

	local SidebarLine = Library:Create('Frame', {
		BackgroundColor3 = Library.BorderColor;
		BorderSizePixel = 0;
		Position = UDim2.new(1, -1, 0, 0);
		Size = UDim2.new(0, 1, 1, 0);
		ZIndex = 3;
		Parent = Sidebar;
	});
	Library:AddToRegistry(SidebarLine, { BackgroundColor3 = 'BorderColor'; });

	local TabArea = Library:Create('ScrollingFrame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 0, 0, 0);
		Size = UDim2.new(1, -1, 1, -74);
		CanvasSize = UDim2.new(0, 0, 0, 0);
		AutomaticCanvasSize = Enum.AutomaticSize.Y;
		ScrollingDirection = Enum.ScrollingDirection.Y;
		ScrollBarThickness = 0;
		ZIndex = 3;
		Parent = Sidebar;
	});

	local TabListLayout = Library:Create('UIListLayout', {
		Padding = UDim.new(0, math.max(Config.TabPadding, 3));
		FillDirection = Enum.FillDirection.Vertical;
		SortOrder = Enum.SortOrder.LayoutOrder;
		Parent = TabArea;
	});

	Library:Create('UIPadding', {
		PaddingTop = UDim.new(0, 8);
		PaddingLeft = UDim.new(0, 8);
		PaddingRight = UDim.new(0, 8);
		Parent = TabArea;
	});

	-- one shared highlight that glides between tabs
	local TabIndicator = Library:Create('Frame', {
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.fromOffset(8, 8);
		Size = UDim2.new(1, -17, 0, 28);
		Visible = false;
		ZIndex = 3;
		Parent = Sidebar;
	});

	Library:AddCorner(TabIndicator, 6);
	Library:AddToRegistry(TabIndicator, { BackgroundColor3 = 'AccentColor'; });

	Library:Create('UIGradient', {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.72),
			NumberSequenceKeypoint.new(1, 0.94),
		});
		Parent = TabIndicator;
	});

	local IndicatorBar = Library:Create('Frame', {
		AnchorPoint = Vector2.new(0, 0.5);
		BackgroundColor3 = Library.AccentColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 0, 0.5, 0);
		Size = UDim2.new(0, 3, 0.55, 0);
		ZIndex = 4;
		Parent = TabIndicator;
	});

	Library:AddCorner(IndicatorBar, 2);
	Library:AddToRegistry(IndicatorBar, { BackgroundColor3 = 'AccentColor'; });

	local ActiveTabButton = nil;

	local function MoveIndicator(Instant)
		if not ActiveTabButton then
			return;
		end;

		local Scale = math.max(BodyScale.Scale, 0.01);
		local Y = (ActiveTabButton.AbsolutePosition.Y - Sidebar.AbsolutePosition.Y) / Scale;
		local H = ActiveTabButton.AbsoluteSize.Y / Scale;

		local TargetPos = UDim2.fromOffset(8, Y);
		local TargetSize = UDim2.new(1, -17, 0, H);

		if Instant or not TabIndicator.Visible then
			Library:SetNow(TabIndicator, 'Position', TargetPos);
			Library:SetNow(TabIndicator, 'Size', TargetSize);
			TabIndicator.Visible = true;
		else
			Library:Tween(TabIndicator, { Position = TargetPos; Size = TargetSize; }, 0.5);

			-- the bar squashes while travelling and springs back on arrival
			Library:SetNow(IndicatorBar, 'Size', UDim2.new(0, 3, 0.2, 0));
			Library:Tween(IndicatorBar, { Size = UDim2.new(0, 3, 0.55, 0) }, 0.6, Enum.EasingStyle.Back);
		end;
	end;

	TabArea:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
		MoveIndicator(true);
	end);

	TabListLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
		task.defer(MoveIndicator, true);
	end);

	local Footer = Library:Create('Frame', {
		BackgroundTransparency = 1;
		Position = UDim2.new(0, 0, 1, -72);
		Size = UDim2.new(1, -1, 0, 72);
		ZIndex = 3;
		Parent = Sidebar;
	});

	local FooterLine = Library:Create('Frame', {
		BackgroundColor3 = Library.BorderColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 10, 0, 0);
		Size = UDim2.new(1, -20, 0, 1);
		ZIndex = 4;
		Parent = Footer;
	});
	Library:AddToRegistry(FooterLine, { BackgroundColor3 = 'BorderColor'; });

	local FooterLogo = Library:Create('ImageLabel', {
		BackgroundColor3 = Library.MainColor;
		BorderSizePixel = 0;
		AnchorPoint = Vector2.new(0.5, 0);
		Position = UDim2.new(0.5, 0, 0, 9);
		Size = UDim2.new(0, 32, 0, 32);
		Image = Config.Logo or '';
		Visible = Config.Logo ~= nil;
		ZIndex = 4;
		Parent = Footer;
	});
	Library:AddCorner(FooterLogo, 8);
	Library:AddStroke(FooterLogo, 'BorderColor');
	Library:AddToRegistry(FooterLogo, {
		BackgroundColor3 = 'MainColor';
	});

	local FooterTitle = Library:CreateLabel({
		Position = UDim2.new(0, 0, 0, 45);
		Size = UDim2.new(1, 0, 0, 12);
		Font = Library.FontBold;
		Text = Config.FooterTitle or Window.Crumbs[1] or '';
		TextSize = 12;
		ZIndex = 4;
		Parent = Footer;
	});
	FooterTitle.TextColor3 = Library.AccentColor;
	Library.RegistryMap[FooterTitle].Properties.TextColor3 = 'AccentColor';

	local FooterSub = Library:CreateLabel({
		Position = UDim2.new(0, 0, 0, 58);
		Size = UDim2.new(1, 0, 0, 11);
		Text = Config.FooterSubtitle or Window.Crumbs[2] or '';
		TextSize = 11;
		ZIndex = 4;
		Parent = Footer;
	});
	FooterSub.TextColor3 = Library.DimFontColor;
	Library.RegistryMap[FooterSub].Properties.TextColor3 = 'DimFontColor';

	-- Username privacy: name, @handle and avatar all follow Library:SetShowName()
	-- (only when the script passes a footer: otherwise these show the window title, which is not a user name)
	if Config.FooterTitle then
		Library:RegisterPrivate(FooterTitle, FooterTitle.Text, 'User');
	end;
	if Config.FooterSubtitle then
		Library:RegisterPrivate(FooterSub, FooterSub.Text, 'Hidden');
	end;

	local LogoMask = Library:CreateLabel({
		Font = Library.FontBold; Size = UDim2.fromScale(1, 1); Text = '?'; TextSize = 16; Visible = false; ZIndex = 5; Parent = FooterLogo;
	});

	Library:OnShowNameChanged(function(Show)
		FooterLogo.Image = Show and (Config.Logo or '') or '';
		LogoMask.Visible = (not Show) and Config.Logo ~= nil;
	end);

	-- Content area
	local TabContainer = Library:Create('Frame', {
		BackgroundTransparency = 1;
		BorderSizePixel = 0;
		Position = UDim2.new(0, SidebarWidth, 0, HeaderHeight);
		Size = UDim2.new(1, -SidebarWidth, 1, -HeaderHeight);
		ClipsDescendants = true;
		ZIndex = 2;
		Parent = Inner;
	});

	-- overlay for the theme tab transitions: decoration only, never takes input
	local TransLayer = Library:Create('Frame', {
		Name = 'TransitionLayer'; BackgroundTransparency = 1; BorderSizePixel = 0; ClipsDescendants = true;
		Size = UDim2.fromScale(1, 1); ZIndex = 12; Parent = TabContainer;
	});
	FX.TransLayer = TransLayer;

	local InnerVideoBackground = Library:Create('VideoFrame', {
		BackgroundColor3 = Library.MainColor;
		BorderSizePixel = 0;
		Position = UDim2.new(0, 0, 0, 0);
		Size = UDim2.new(1, 0, 1, 0);
		ZIndex = 2;
		Visible = false;
		Volume = 0;
		Looped = true;
		Parent = TabContainer;
	});
	Library.InnerVideoBackground = InnerVideoBackground;

	function Window:SetWindowTitle(Title)
		BuildCrumbs(Title);
	end;

	-- turn the accessories on / off at runtime
	function Window:SetAccessories(Bool)
		Accessories.Enabled = (not not Bool);
		Accessories:Show(Accessories.Enabled and Outer.Visible);

		if Accessories.Enabled then
			Accessories:Rebuild();

			if Library.Toggled then
				Accessories:Reset();
				Accessories:Open();
			end;
		end;
	end;

	-- size in px, the same unit as Config.AccessorySize (about 60% of the window height is normal); pieces are rebuilt at the new size
	function Window:SetAccessorySize(Size)
		if type(Size) ~= 'number' or Size <= 0 then
			return;
		end;

		local Scale = math.clamp(Size / AccNormal, 0.6, 1.3);
		if math.abs(Scale - Accessories.Scale) < 0.005 then
			return;
		end;

		Accessories.Scale = Scale;
		Accessories:Rebuild();

		if Library.Toggled then
			Accessories:Show(true);
		end;
	end;

	function Window:GetAccessorySize()
		return AccNormal * Accessories.Scale;
	end;

	-- older names
	function Window:SetWings(Bool) Window:SetAccessories(Bool); end;
	function Window:SetWingSize(Size) Window:SetAccessorySize(Size); end;
	function Window:GetWingSize() return Window:GetAccessorySize(); end;

	Window.Accessories = Accessories;
	Window.Wings = Accessories; -- older scripts

	FX.AccessoryHook = function()
		Accessories:Rebuild();
	end;

-- [[rig:acchook]]
	FX.AccessoryKick = function(Power)
		Accessories:Kick(Power);
	end;
-- [[/rig:acchook]]
	-- first build now that the scene is known (Window:SetScene / the theme manager change it later and call the hook)
	if AccR then
		Accessories:Rebuild();
	end;
	Window.FX = FX;

	-- pick an animated scene by name (nil / 'None' = clean).
	function Window:SetScene(Name)
		local Scene = FX.Scenes[Name];


		FX:SetScene(Name);
		return true;
	end;

	-- UI-only looks (they change how this window is drawn, nothing in the game)
	function Window:SetGlowMode(On)
		Library.GlowMode = On == true;

		if Outer.Visible then
			StartGlow();
		end;
	end;

	function Window:SetRGBBorder(On)
		Library.RGBBorder = On == true;
		BorderGradient.Color = BorderColors();
	end;

	function Window:SetCinematic(On)
		On = On == true;
		Library.Cinematic = On;
		FX.TimeScale = On and 0.55 or 1;
		FX:QueueRebuild(0.05); -- tweens read the time scale when they are created, so rebuild the scene

		if On then
			CineHolder.Visible = true;
		end;

		for _, Edge in ipairs(CineEdges) do
			Library:Tween(Edge, { BackgroundTransparency = On and 0 or 1 }, 0.7);
		end;

		if not On then
			task.delay(0.75 * Library.AnimationSpeed, function()
				if not Library.Cinematic then
					CineHolder.Visible = false;
				end;
			end);
		end;
	end;

	-- Search: filters elements of every groupbox by their text
	function Window:ApplySearch()
		local Query = string.lower(SearchBox.Text or '');
		for _, T in next, Window.Tabs do
			for _, Box in next, T.Groupboxes do
				if Box.ApplyFilter then
					Box:ApplyFilter(Query);
				end;
			end;
		end;
		Library:UpdateDependencyBoxes();
	end;

	SearchBox:GetPropertyChangedSignal('Text'):Connect(function()
		Window:ApplySearch();
	end);

	function Window:AddTab(Name)
		local Tab = {
			Groupboxes = {};
			Tabboxes = {};
			Index = Library.TotalTabs + 1;
		};

		local TabButton = Library:Create('Frame', {
			BackgroundColor3 = Library.FontColor;
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Size = UDim2.new(1, 0, 0, TouchSize(28));
			ZIndex = 4;
			Parent = TabArea;
		});

		Library:AddCorner(TabButton, 6);
		Library:AddToRegistry(TabButton, {
			BackgroundColor3 = 'FontColor';
		});

		local TabButtonLabel = Library:CreateLabel({
			Position = UDim2.new(0, 12, 0, 0);
			Size = UDim2.new(1, -14, 1, 0);
			Font = Library.FontMedium;
			Text = Name;
			TextSize = 13;
			TextXAlignment = Enum.TextXAlignment.Left;
			TextTruncate = Enum.TextTruncate.AtEnd;
			ZIndex = 5;
			Parent = TabButton;
		});
		TabButtonLabel.TextColor3 = Library.DimFontColor;
		Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = 'DimFontColor';

		local TabFrame = Library:CreateCanvas({
			Name = 'TabFrame',
			BackgroundTransparency = 1;
			BorderSizePixel = 0;
			Position = UDim2.new(0, 0, 0, 0);
			Size = UDim2.new(1, 0, 1, 0);
			Visible = false;
			ZIndex = 2;
			Parent = TabContainer;
		});

		local function CreateSide(Position, Size)
			local Side = Library:Create('ScrollingFrame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Position = Position;
				Size = Size;
				CanvasSize = UDim2.new(0, 0, 0, 0);
				BottomImage = '';
				TopImage = '';
				ScrollBarThickness = 2;
				ScrollBarImageColor3 = Library.AccentColor;
				ZIndex = 2;
				Parent = TabFrame;
			});
			Library:AddToRegistry(Side, { ScrollBarImageColor3 = 'AccentColor'; });

			Library:Create('UIListLayout', {
				Padding = UDim.new(0, 10);
				FillDirection = Enum.FillDirection.Vertical;
				SortOrder = Enum.SortOrder.LayoutOrder;
				HorizontalAlignment = Enum.HorizontalAlignment.Center;
				Parent = Side;
			});

			Library:Create('UIPadding', {
				PaddingTop = UDim.new(0, 1);
				PaddingBottom = UDim.new(0, 1);
				Parent = Side;
			});

			return Side;
		end;

		local LeftSidePos = UDim2.new(0, 10, 0, 10);
		local RightSidePos = UDim2.new(0.5, 5, 0, 10);
		local LeftSide = CreateSide(LeftSidePos, UDim2.new(0.5, -15, 1, -20));
		local RightSide = CreateSide(RightSidePos, UDim2.new(0.5, -15, 1, -20));

		if Library.IsMobile then
			local SidesValues = {
				["Left"] = tick(),
				["Right"] = tick(),
			}

			LeftSide:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
				Library.CanDrag = false;

				local ChangeTick = tick();
				SidesValues.Left = ChangeTick;
				task.wait(0.15);

				if SidesValues.Left == ChangeTick then
					Library.CanDrag = true;
				end
			end);

			RightSide:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
				Library.CanDrag = false;

				local ChangeTick = tick();
				SidesValues.Right = ChangeTick;
				task.wait(0.15);

				if SidesValues.Right == ChangeTick then
					Library.CanDrag = true;
				end
			end);
		end;

		-- the layout is kept in a local: looking it up by name again later fails once the menu is being torn down
		for _, Side in next, { LeftSide, RightSide } do
			local SideLayout = Side:FindFirstChildOfClass('UIListLayout');

			if SideLayout then
				SideLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
					if Side.Parent then
						Side.CanvasSize = UDim2.fromOffset(0, SideLayout.AbsoluteContentSize.Y + 2);
					end;
				end);
			end;
		end;

		local TabActive = false;
		local TabHovering = false;

		local function RefreshTabButton()
			local LabelIdx = (TabActive or TabHovering) and 'FontColor' or 'DimFontColor';
			Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = LabelIdx;

			Library:Tween(TabButtonLabel, {
				TextColor3 = Library[LabelIdx];
				Position = UDim2.new(0, TabActive and 16 or (TabHovering and 14 or 12), 0, 0);
			}, 0.35);
			Library:Tween(TabButton, { BackgroundTransparency = (TabHovering and not TabActive) and 0.95 or 1 }, 0.25);
		end;

		function Tab:ShowTab()
			Library.ActiveTab = Name;
			for _, OtherTab in next, Window.Tabs do
				if OtherTab ~= Tab then
					OtherTab:HideTab();
				end;
			end;

			local WasActive = TabActive;
			TabActive = true;

			ActiveTabButton = TabButton;
			MoveIndicator();
			RefreshTabButton();

			if not WasActive then
				-- the active theme's transition plays over the tab area (skipped while the menu is still opening)
				if Library.Toggled then
					FX:PlayTransition();
					FX:ReactSigils(Tab.Index); -- the hero behind the menu does its move
				end;

				-- content rises + fades in, right column trails slightly behind the left
				Library:SetGroupTransparency(TabFrame, 1);
				Library:SetNow(LeftSide, 'Position', LeftSidePos + UDim2.fromOffset(0, 16));
				Library:SetNow(RightSide, 'Position', RightSidePos + UDim2.fromOffset(0, 16));
				TabFrame.Visible = true;

				Library:SetGroupTransparency(TabFrame, 0, 0.4);
				Library:Tween(LeftSide, { Position = LeftSidePos }, 0.55);

				task.delay(0.06 * Library.AnimationSpeed, function()
					if TabActive then
						Library:Tween(RightSide, { Position = RightSidePos }, 0.55);
					end;
				end);
			end;
		end;

		function Tab:HideTab()
			TabActive = false;
			RefreshTabButton();

			TabFrame.Visible = false;
			Library:SetNow(LeftSide, 'Position', LeftSidePos);
			Library:SetNow(RightSide, 'Position', RightSidePos);
		end;

		TabButton.MouseEnter:Connect(function()
			TabHovering = true;
			RefreshTabButton();
		end);

		TabButton.MouseLeave:Connect(function()
			TabHovering = false;
			RefreshTabButton();
		end);

		function Tab:SetLayoutOrder(Position)
			TabButton.LayoutOrder = Position;
		end;

		function Tab:GetSides()
			return { ["Left"] = LeftSide, ["Right"] = RightSide };
		end;

		function Tab:AddGroupbox(Info)
			local Groupbox = {};
			local Hidden = {};

			local BoxOuter = Library:Create('Frame', {
				BackgroundColor3 = Library.MainColor;
				BorderSizePixel = 0;
				Size = UDim2.new(1, -2, 0, 507 + 2);
				ClipsDescendants = true;
				ZIndex = 2;
				Parent = Info.Side == 1 and LeftSide or RightSide;
			});

			Library:AddCorner(BoxOuter, 7);
			local BoxStroke = Library:AddStroke(BoxOuter, 'BorderColor');
			Library:RegisterPanel(BoxOuter); -- turns slightly translucent while a theme scene is drawn behind it

			Library:AddToRegistry(BoxOuter, {
				BackgroundColor3 = 'MainColor';
			});

			BoxOuter.MouseEnter:Connect(function()
				Library:Tween(BoxStroke, { Color = Library.BorderColor:Lerp(Library.AccentColor, 0.35) }, 0.3);
			end);

			BoxOuter.MouseLeave:Connect(function()
				Library:Tween(BoxStroke, { Color = Library.BorderColor }, 0.45);
			end);

			local BoxInner = Library:Create('Frame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 4;
				Parent = BoxOuter;
			});

			local TitleBar = Library:Create('Frame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 0, 28);
				ZIndex = 5;
				Parent = BoxInner;
			});

			local Highlight = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0, 0.5);
				BackgroundColor3 = Library.AccentColor;
				BorderSizePixel = 0;
				Position = UDim2.new(0, 10, 0.5, 0);
				Size = UDim2.new(0, 3, 0, 12);
				ZIndex = 6;
				Parent = TitleBar;
			});

			Library:AddCorner(Highlight, 2);
			Library:AddToRegistry(Highlight, {
				BackgroundColor3 = 'AccentColor';
			});

			local GroupboxLabel = Library:CreateLabel({
				Size = UDim2.new(1, -24, 1, 0);
				Position = UDim2.new(0, 20, 0, 0);
				Font = Library.FontBold;
				TextSize = 13;
				Text = Info.Name;
				TextXAlignment = Enum.TextXAlignment.Left;
				ZIndex = 6;
				Parent = TitleBar;
			});

			local TitleLine = Library:Create('Frame', {
				BackgroundColor3 = Library.BorderColor;
				BorderSizePixel = 0;
				Position = UDim2.new(0, 0, 0, 28);
				Size = UDim2.new(1, 0, 0, 1);
				ZIndex = 5;
				Parent = BoxInner;
			});

			Library:AddToRegistry(TitleLine, {
				BackgroundColor3 = 'BorderColor';
			});

			local Container = Library:Create('Frame', {
				BackgroundTransparency = 1;
				Position = UDim2.new(0, 10, 0, 34);
				Size = UDim2.new(1, -16, 1, -34);
				ZIndex = 1;
				Parent = BoxInner;
			});

			Library:Create('UIListLayout', {
				FillDirection = Enum.FillDirection.Vertical;
				SortOrder = Enum.SortOrder.LayoutOrder;
				Parent = Container;
			});

			function Groupbox:Resize()
				local Size = 0;

				for _, Element in next, Groupbox.Container:GetChildren() do
					if (not Element:IsA('UIListLayout')) and Element.Visible then
						Size = Size + Element.Size.Y.Offset;
					end;
				end;

				local Target = UDim2.new(1, -2, 0, 34 + Size + 6);

				if Library.Toggled and TabFrame.Visible then
					Library:Tween(BoxOuter, { Size = Target }, 0.4);
				else
					Library:SetNow(BoxOuter, 'Size', Target);
				end;
			end;

			-- Used by the header search box
			function Groupbox:ApplyFilter(Query)
				for Element, WasVisible in next, Hidden do
					if Element.Parent then
						Element.Visible = WasVisible;
					end;
				end;
				Hidden = {};

				if Query == '' then
					BoxOuter.Visible = true;
					Groupbox:Resize();
					return;
				end;

				local NameMatch = string.find(string.lower(Info.Name or ''), Query, 1, true) ~= nil;
				local AnyMatch = NameMatch;

				for _, Element in next, Container:GetChildren() do
					if (not Element:IsA('UIListLayout')) and Element.Visible then
						local Matched = NameMatch;

						if not Matched then
							local Text = '';
							for _, Desc in next, Element:GetDescendants() do
								if Desc:IsA('TextLabel') or Desc:IsA('TextButton') then
									Text = Text .. string.lower(Desc.Text) .. ' ';
								end;
							end;
							Matched = string.find(Text, Query, 1, true) ~= nil;
						end;

						if Matched then
							AnyMatch = true;
						else
							Hidden[Element] = true;
							Element.Visible = false;
						end;
					end;
				end;

				BoxOuter.Visible = AnyMatch;
				Groupbox:Resize();
			end;

			Groupbox.Container = Container;
			Groupbox.Holder = BoxOuter;
			setmetatable(Groupbox, BaseGroupbox);

			Groupbox:AddBlank(3);
			Groupbox:Resize();

			Tab.Groupboxes[Info.Name] = Groupbox;

			return Groupbox;
		end;

		function Tab:AddLeftGroupbox(Name)
			return Tab:AddGroupbox({ Side = 1; Name = Name; });
		end;

		function Tab:AddRightGroupbox(Name)
			return Tab:AddGroupbox({ Side = 2; Name = Name; });
		end;

		function Tab:AddTabbox(Info)
			local Tabbox = {
				Tabs = {};
			};

			local Order = {};
			local ActiveSub = nil;

			local BoxOuter = Library:Create('Frame', {
				BackgroundColor3 = Library.MainColor;
				BorderSizePixel = 0;
				ClipsDescendants = true;
				Size = UDim2.new(1, -2, 0, 0);
				ZIndex = 2;
				Parent = Info.Side == 1 and LeftSide or RightSide;
			});

			Library:AddCorner(BoxOuter, 7);
			local BoxStroke = Library:AddStroke(BoxOuter, 'BorderColor');
			Library:RegisterPanel(BoxOuter); -- turns slightly translucent while a theme scene is drawn behind it

			Library:AddToRegistry(BoxOuter, {
				BackgroundColor3 = 'MainColor';
			});

			BoxOuter.MouseEnter:Connect(function()
				Library:Tween(BoxStroke, { Color = Library.BorderColor:Lerp(Library.AccentColor, 0.35) }, 0.3);
			end);

			BoxOuter.MouseLeave:Connect(function()
				Library:Tween(BoxStroke, { Color = Library.BorderColor }, 0.45);
			end);

			local BoxInner = Library:Create('Frame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 4;
				Parent = BoxOuter;
			});

			local TabboxButtons = Library:Create('Frame', {
				BackgroundTransparency = 1;
				Position = UDim2.new(0, 0, 0, 0);
				Size = UDim2.new(1, 0, 0, 28);
				ZIndex = 5;
				Parent = BoxInner;
			});

			Library:Create('UIListLayout', {
				FillDirection = Enum.FillDirection.Horizontal;
				HorizontalAlignment = Enum.HorizontalAlignment.Left;
				SortOrder = Enum.SortOrder.LayoutOrder;
				Parent = TabboxButtons;
			});

			local ButtonsLine = Library:Create('Frame', {
				BackgroundColor3 = Library.BorderColor;
				BorderSizePixel = 0;
				Position = UDim2.new(0, 0, 0, 28);
				Size = UDim2.new(1, 0, 0, 1);
				ZIndex = 5;
				Parent = BoxInner;
			});

			Library:AddToRegistry(ButtonsLine, {
				BackgroundColor3 = 'BorderColor';
			});

			-- underline that slides to the selected sub-tab
			local Underline = Library:Create('Frame', {
				AnchorPoint = Vector2.new(0.5, 0);
				BackgroundColor3 = Library.AccentColor;
				BorderSizePixel = 0;
				Position = UDim2.new(0.5, 0, 0, 27);
				Size = UDim2.new(0, 0, 0, 2);
				ZIndex = 8;
				Parent = BoxInner;
			});

			Library:AddCorner(Underline, 1);
			Library:AddToRegistry(Underline, {
				BackgroundColor3 = 'AccentColor';
			});

			local function MoveUnderline(Instant)
				local Index = table.find(Order, ActiveSub);
				if not Index then
					return;
				end;

				local Width = 1 / #Order;
				local Target = {
					Position = UDim2.new(Width * (Index - 0.5), 0, 0, 27);
					Size = UDim2.new(Width, -24, 0, 2);
				};

				Library:Tween(Underline, Target, Instant and 0 or 0.45);
			end;

			function Tabbox:AddTab(Name)
				local Tab = {};

				local Button = Library:Create('Frame', {
					BackgroundTransparency = 1;
					BorderSizePixel = 0;
					Size = UDim2.new(0.5, 0, 1, 0);
					ZIndex = 6;
					Parent = TabboxButtons;
				});

				local ButtonLabel = Library:CreateLabel({
					Size = UDim2.new(1, 0, 1, 0);
					Font = Library.FontMedium;
					TextSize = 13;
					Text = Name;
					TextXAlignment = Enum.TextXAlignment.Center;
					ZIndex = 7;
					Parent = Button;
				});

				ButtonLabel.TextColor3 = Library.DimFontColor;
				Library.RegistryMap[ButtonLabel].Properties.TextColor3 = 'DimFontColor';

				local Container = Library:Create('Frame', {
					BackgroundTransparency = 1;
					Position = UDim2.new(0, 10, 0, 34);
					Size = UDim2.new(1, -16, 1, -34);
					ZIndex = 1;
					Visible = false;
					Parent = BoxInner;
				});

				Library:Create('UIListLayout', {
					FillDirection = Enum.FillDirection.Vertical;
					SortOrder = Enum.SortOrder.LayoutOrder;
					Parent = Container;
				});

				local SubHovering = false;

				local function RefreshLabel()
					local Idx = (ActiveSub == Tab or SubHovering) and 'FontColor' or 'DimFontColor';
					Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Idx;
					Library:Tween(ButtonLabel, { TextColor3 = Library[Idx] }, 0.3);
				end;

				Button.MouseEnter:Connect(function() SubHovering = true; RefreshLabel(); end);
				Button.MouseLeave:Connect(function() SubHovering = false; RefreshLabel(); end);

				function Tab:Show()
					local First = ActiveSub == nil;

					for _, Tab in next, Tabbox.Tabs do
						Tab:Hide();
					end;

					ActiveSub = Tab;
					Container.Visible = true;
					RefreshLabel();
					MoveUnderline(First);

					Tab:Resize();
				end;

				function Tab:Hide()
					Container.Visible = false;
					if ActiveSub == Tab then
						ActiveSub = nil;
					end;
					RefreshLabel();
				end;

				function Tab:Resize()
					local TabCount = #Order;

					for _, Button in next, TabboxButtons:GetChildren() do
						if not Button:IsA('UIListLayout') then
							Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
						end;
					end;

					MoveUnderline(true);

					if (not Container.Visible) then
						return;
					end;

					local Size = 0;

					for _, Element in next, Tab.Container:GetChildren() do
						if (not Element:IsA('UIListLayout')) and Element.Visible then
							Size = Size + Element.Size.Y.Offset;
						end;
					end;

					local Target = UDim2.new(1, -2, 0, 34 + Size + 6);

					if Library.Toggled and TabFrame.Visible then
						Library:Tween(BoxOuter, { Size = Target }, 0.4);
					else
						Library:SetNow(BoxOuter, 'Size', Target);
					end;
				end;

				Library:OnTap(Button, function(Input)
					if not Library:MouseIsOverOpenedFrame(Input) then
						if ActiveSub ~= Tab then
							Tab:Show();
							MoveUnderline();
						end;
						Tab:Resize();
					end;
				end);

				Tab.Container = Container;
				Tabbox.Tabs[Name] = Tab;
				table.insert(Order, Tab);

				setmetatable(Tab, BaseGroupbox);

				Tab:AddBlank(3);
				Tab:Resize();

				-- Show the first tab
				if #Order == 1 then
					Tab:Show();
				end;

				return Tab;
			end;

			Tab.Tabboxes[Info.Name or ''] = Tabbox;

			return Tabbox;
		end;

		function Tab:AddLeftTabbox(Name)
			return Tab:AddTabbox({ Name = Name, Side = 1; });
		end;

		function Tab:AddRightTabbox(Name)
			return Tab:AddTabbox({ Name = Name, Side = 2; });
		end;

		Library:OnTap(TabButton, function(Input)
			do
				Tab:ShowTab();
			end;
		end);

		-- This was the first tab added, so we show it by default.
		Library.TotalTabs = Library.TotalTabs + 1;
		if Library.TotalTabs == 1 then
			Tab:ShowTab();
			task.defer(MoveIndicator, true);
		end;

		Window.Tabs[Name] = Tab;
		return Tab;
	end;

	local ModalElement = Library:Create('TextButton', {
		BackgroundTransparency = 1;
		Size = UDim2.new(0, 0, 0, 0);
		Visible = true;
		Text = '';
		Modal = false;
		Parent = ScreenGui;
	});

	local Toggled = false;
	local ToggleToken = 0;

	-- open: window pops up from 92% with a soft overshoot while everything fades in
	-- close: shrinks slightly and fades out
	function Library:Toggle()
		local FadeTime = Config.MenuFadeTime;
		Toggled = (not Toggled);
		Library.Toggled = Toggled;
		ModalElement.Modal = Toggled;

		ToggleToken = ToggleToken + 1;
		local Token = ToggleToken;

		for _, Option in pairs(Options) do
			if Option.Type == 'Dropdown' and Option.CloseDropdown then
				Option:CloseDropdown()
			elseif Option.Type == 'ColorPicker' and Option.Hide then
				Option:Hide()
			end
		end

		if Toggled then
			if not Outer.Visible then
				Library:SetNow(BodyScale, 'Scale', 0.92);
				Library:SetGroupTransparency(Inner, 1);
				Library:SetNow(InnerStroke, 'Transparency', 1);
				Library:SetNow(Shadow, 'ImageTransparency', 1);
				Wings:Reset();
				Outer.Visible = true;
			end;

			Wings:Open(FadeTime); -- same fade time as the window

			Library:Tween(BodyScale, { Scale = 1 }, FadeTime * 1.5, Enum.EasingStyle.Back);
			Library:SetGroupTransparency(Inner, 0, FadeTime);
			Library:Tween(InnerStroke, { Transparency = 0 }, FadeTime);
			Library:Tween(Shadow, { ImageTransparency = ShadowTransparency }, FadeTime * 1.5);

			if Library.GlowMode then
				StartGlow();
			end;

			FX:_Sync(); -- effects only run while the menu is open

			task.defer(MoveIndicator, true);
		else
			local CloseTime = FadeTime * 0.75;

			Library:Tween(BodyScale, { Scale = 0.95 }, CloseTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			Library:SetGroupTransparency(Inner, 1, CloseTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			Library:Tween(InnerStroke, { Transparency = 1 }, CloseTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			StopGlow();
			Library:Tween(Shadow, { ImageTransparency = 1 }, CloseTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In);
			Wings:Close(CloseTime);

			task.delay(CloseTime * Library.AnimationSpeed, function()
				if ToggleToken == Token then
					Outer.Visible = false;
					FX:_Sync(); -- stop the shared effects loop
				end;
			end);
		end;
	end
	Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
		if type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' then
			if Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value then
				task.spawn(Library.Toggle)
			end
		elseif Input.KeyCode == Enum.KeyCode.RightControl or (Input.KeyCode == Enum.KeyCode.RightShift and (not Processed)) then
			task.spawn(Library.Toggle)
		end
	end));

	if Library.IsMobile then
		if Library.IsMobile then
			local ToggleUIOuter = Library:Create('Frame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Position = UDim2.new(0, 10, 0, 10);
				Size = UDim2.new(0, 100, 0, 36);
				ZIndex = 200;
				Visible = true;
				Parent = ScreenGui;
			});
		
			local ToggleUIInner = Library:Create('Frame', {
				BackgroundColor3 = Library.MainColor;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 201;
				Parent = ToggleUIOuter;
			});

			Library:AddCorner(ToggleUIInner, 7);
			Library:AddStroke(ToggleUIInner, 'AccentColor');
		
			Library:AddToRegistry(ToggleUIInner, {
				BorderColor3 = 'AccentColor';
			});
		
			local ToggleUIInnerFrame = Library:Create('Frame', {
				BackgroundColor3 = Color3.new(1, 1, 1);
				BorderSizePixel = 0;
				Position = UDim2.new(0, 1, 0, 1);
				Size = UDim2.new(1, -2, 1, -2);
				ZIndex = 202;
				Parent = ToggleUIInner;
			});

			Library:AddCorner(ToggleUIInnerFrame, 6);
		
			local ToggleUIGradient = Library:Create('UIGradient', {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
					ColorSequenceKeypoint.new(1, Library.MainColor),
				});
				Rotation = -90;
				Parent = ToggleUIInnerFrame;
			});
		
			Library:AddToRegistry(ToggleUIGradient, {
				Color = function()
					return ColorSequence.new({
						ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
						ColorSequenceKeypoint.new(1, Library.MainColor),
					});
				end
			});
		
			local ToggleUIButton = Library:Create('TextButton', {
				Position = UDim2.new(0, 5, 0, 0);
				Size = UDim2.new(1, -4, 1, 0);
				BackgroundTransparency = 1;
				Font = Library.Font;
				Text = "Hide UI";
				TextColor3 = Library.FontColor;
				TextSize = 14;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextStrokeTransparency = 0;
				ZIndex = 203;
				Parent = ToggleUIInnerFrame;
			});
		
			Library:MakeDraggable(ToggleUIOuter);
		
			Library:OnTap(ToggleUIButton, function()
				Library:Toggle()
				ToggleUIButton.Text = Library.Toggled and "Unhide UI" or "Hide UI"
			end)
			-- Lock UI Button
			local LockUIOuter = Library:Create('Frame', {
				BackgroundTransparency = 1;
				BorderSizePixel = 0;
				Position = UDim2.new(0, 10, 0, 54);
				Size = UDim2.new(0, 100, 0, 36);
				ZIndex = 200;
				Visible = true;
				Parent = ScreenGui;
			});
		
			local LockUIInner = Library:Create('Frame', {
				BackgroundColor3 = Library.MainColor;
				BorderSizePixel = 0;
				Size = UDim2.new(1, 0, 1, 0);
				ZIndex = 201;
				Parent = LockUIOuter;
			});

			Library:AddCorner(LockUIInner, 7);
			Library:AddStroke(LockUIInner, 'AccentColor');
		
			Library:AddToRegistry(LockUIInner, {
				BorderColor3 = 'AccentColor';
			});
		
			local LockUIInnerFrame = Library:Create('Frame', {
				BackgroundColor3 = Color3.new(1, 1, 1);
				BorderSizePixel = 0;
				Position = UDim2.new(0, 1, 0, 1);
				Size = UDim2.new(1, -2, 1, -2);
				ZIndex = 202;
				Parent = LockUIInner;
			});

			Library:AddCorner(LockUIInnerFrame, 6);
		
			local LockUIGradient = Library:Create('UIGradient', {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
					ColorSequenceKeypoint.new(1, Library.MainColor),
				});
				Rotation = -90;
				Parent = LockUIInnerFrame;
			});
		
			Library:AddToRegistry(LockUIGradient, {
				Color = function()
					return ColorSequence.new({
						ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
						ColorSequenceKeypoint.new(1, Library.MainColor),
					});
				end
			});
		
			local LockUIButton = Library:Create('TextButton', {
				Position = UDim2.new(0, 5, 0, 0);
				Size = UDim2.new(1, -4, 1, 0);
				BackgroundTransparency = 1;
				Font = Library.Font;
				Text = "Lock UI";
				TextColor3 = Library.FontColor;
				TextSize = 14;
				TextXAlignment = Enum.TextXAlignment.Left;
				TextStrokeTransparency = 0;
				ZIndex = 203;
				Parent = LockUIInnerFrame;
			});
		
			Library:MakeDraggable(LockUIOuter);
		
			Library:OnTap(LockUIButton, function()
				Library.CantDragForced = not Library.CantDragForced;
				LockUIButton.Text = Library.CantDragForced and "Unlock UI" or "Lock UI"
				LockUIInner.BackgroundColor3 = Library.CantDragForced and Color3.new(1, 0, 0) or Library.MainColor
			end)
		end
	end 

	if Config.AutoShow then task.spawn(Library.Toggle) end

	Window.Holder = Outer;

	Library.Window = Window;
	return Window;
end;

local function OnPlayerChange()
	local PlayerList = GetPlayersString();

	for _, Value in next, Options do
		if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
			Value:SetValues(PlayerList);
		end;
	end;
end;

Players.PlayerAdded:Connect(OnPlayerChange);
Players.PlayerRemoving:Connect(OnPlayerChange);

getgenv().Library = Library;

return Library;
-- yo
