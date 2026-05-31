using Godot;
using WeatherSystem;

public partial class WeatherManager : Node3D
{
	[Export] public WeatherState CurrentState;
	[Export] public WeatherState TargetState;
	[Export] public float TransitionDuration = 5.0f;
	[Export] private Node _precipitationSystem;
	[Export] private Node _snowSystem;

	[Export] private float snowStartPrecip  = 0.45f;
	[Export] private float snowFullPrecip   = 0.75f;
	[Export] private float rainEndPrecip    = 0.65f;
	[Export] private float stormPrecipWeight = 0.65f;
	[Export] private float stormNimboWeight  = 0.70f;

	private float _transitionTimer = 0.0f;
	private WeatherState _startState;
	private bool _transitioning  = false;
	private bool _stormActive    = false;

	// Fix 1: track last-pushed precipitation values so we only Call() GDScript
	// when they actually change — stops 60 redundant cross-language calls/sec
	private float _lastRainIntensity = -1f;
	private float _lastDrizzleBlend  = -1f;
	private float _lastSnowIntensity = -1f;
	private float _lastWindSpeed     = -1f;

	// Fix 2: throttle WeatherUpdated signal — cloud controllers don't need
	// 60 updates/sec, they lerp internally. Fire at most every N seconds.
	private const float SIGNAL_INTERVAL = 0.1f;   // 10 Hz is plenty
	private float _signalTimer = 0f;

	[Signal] public delegate void StormStateChangedEventHandler(bool active);
	[Signal] public delegate void WeatherTransitionStartedEventHandler(WeatherState TargetState);
	[Signal] public delegate void WeatherTransitionCompletedEventHandler(WeatherState finalState);
	[Signal] public delegate void WeatherUpdatedEventHandler(WeatherState CurrentState);

	public override void _Ready()
	{
		GD.Print("WeatherManager Ready");
		if (TargetState == null || CurrentState == null)
		{
			GD.Print("❌ Weather states are not assigned in the inspector!");
			return;
		}
		GD.Print("✅ Weather states are assigned in the inspector!");
		SetWeather(TargetState);
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;

		// ── Transition tick ────────────────────────────────────────
		if (_transitioning && TargetState != null && CurrentState != null)
		{
			_transitionTimer += dt;
			float t = Mathf.Clamp(_transitionTimer / TransitionDuration, 0f, 1f);
			InterpolateState(t);
			DeriveRainFromClouds();

			if (t >= 1.0f)
			{
				_transitioning = false;
				EmitSignal(SignalName.WeatherTransitionCompleted, CurrentState);
				GD.Print("Transition complete");

				// Force a signal and precipitation push at transition end
				// so all systems land exactly on the final state
				_signalTimer = SIGNAL_INTERVAL;
				_lastRainIntensity = -1f;
				_lastDrizzleBlend  = -1f;
				_lastSnowIntensity = -1f;
				_lastWindSpeed     = -1f;
			}
		}
		else if (!_transitioning)
		{
			// Fix 3: DeriveRainFromClouds only needed when transitioning.
			// When settled, values are stable — no need to recompute every frame.
			// We still call it once per signal tick to catch any edge cases.
		}

		// ── Precipitation push — only when values changed ──────────
		float rain  = CurrentState.RainIntensity;
		float drizzle = CurrentState.DrizzleBlend;
		float snow  = CurrentState.SnowIntensity;
		float wind  = CurrentState.WindSpeed;

		bool rainChanged = Mathf.Abs(rain    - _lastRainIntensity) > 0.005f
						|| Mathf.Abs(drizzle - _lastDrizzleBlend)  > 0.005f;
		bool snowChanged = Mathf.Abs(snow    - _lastSnowIntensity) > 0.005f
						|| Mathf.Abs(wind    - _lastWindSpeed)      > 0.005f;

		if (rainChanged)
		{
			_precipitationSystem?.Call("set_precipitation", rain, drizzle);
			_lastRainIntensity = rain;
			_lastDrizzleBlend  = drizzle;
		}

		if (snowChanged)
		{
			_snowSystem?.Call("set_snow", snow, wind);
			_lastSnowIntensity = snow;
			_lastWindSpeed     = wind;
		}

		// ── Storm detection — runs every frame, cheap bool compare ─
		bool stormy = CurrentState.Precipitation >= stormPrecipWeight &&
					  CurrentState.NimboWeight   >= stormNimboWeight;
		if (stormy != _stormActive)
		{
			_stormActive = stormy;
			EmitSignal(SignalName.StormStateChanged, _stormActive);
			GD.Print(stormy ? "⛈️ STORM ACTIVE" : "🌤️ STORM ENDED");
		}

		// Fix 2: throttle WeatherUpdated to 10 Hz — cloud controllers lerp
		// their own values smoothly, they don't need per-frame target updates
		_signalTimer += dt;
		if (_signalTimer >= SIGNAL_INTERVAL)
		{
			// Fix 3: derive rain here instead of every frame — runs 10x/sec
			// which is more than enough for smooth transitions
			if (_transitioning)
				DeriveRainFromClouds();

			EmitSignal(SignalName.WeatherUpdated, CurrentState);
			_signalTimer = 0f;
		}
	}

	public void SetWeather(WeatherState newState)
	{
		if (newState == null)
		{
			GD.Print("❌ Target weather state is null!");
			return;
		}
		_transitioning = true;
		TargetState    = newState;
		EmitSignal(SignalName.WeatherTransitionStarted, TargetState);
		_startState    = CurrentState.Duplicate() as WeatherState;
		_transitionTimer = 0.0f;
	}

	private void DeriveRainFromClouds()
	{
		float nimbo   = CurrentState.NimboWeight;
		float stratus = CurrentState.StratusWeight;
		float precip  = CurrentState.Precipitation;

		CurrentState.WindSpeed = Mathf.Clamp(CurrentState.WindSpeed, -1.0f, 1.0f);

		CurrentState.RainIntensity = nimbo;
		CurrentState.DrizzleBlend  = Mathf.Clamp(stratus - nimbo, 0f, 1f);

		float snowRaw = Mathf.InverseLerp(snowStartPrecip, snowFullPrecip, precip);
		CurrentState.SnowIntensity = Mathf.Clamp(snowRaw, 0f, 1f) * nimbo;

		float rainFade = Mathf.Clamp(
			Mathf.InverseLerp(rainEndPrecip, snowStartPrecip, precip), 0f, 1f);
		CurrentState.RainIntensity *= rainFade;
		 if (CurrentState.RainIntensity > 0.3f){
			CurrentState.SnowIntensity = 0f;}
	}

	private void InterpolateState(float t)
	{
		CurrentState.Humidity        = Mathf.Lerp(_startState.Humidity,        TargetState.Humidity,        t);
		CurrentState.CloudCoverage   = Mathf.Lerp(_startState.CloudCoverage,   TargetState.CloudCoverage,   t);
		CurrentState.Precipitation   = Mathf.Lerp(_startState.Precipitation,   TargetState.Precipitation,   t);
		CurrentState.WindSpeed       = Mathf.Lerp(_startState.WindSpeed,        TargetState.WindSpeed,       t);
		CurrentState.FogDensity      = Mathf.Lerp(_startState.FogDensity,       TargetState.FogDensity,      t);
		CurrentState.LightMultiplier = Mathf.Lerp(_startState.LightMultiplier,  TargetState.LightMultiplier, t);

		CurrentState.CirrusWeight      = Mathf.Lerp(_startState.CirrusWeight,      TargetState.CirrusWeight,      t);
		CurrentState.AltocumulusWeight = Mathf.Lerp(_startState.AltocumulusWeight, TargetState.AltocumulusWeight, t);
		CurrentState.CumulusWeight     = Mathf.Lerp(_startState.CumulusWeight,     TargetState.CumulusWeight,     t);
		CurrentState.StratusWeight     = Mathf.Lerp(_startState.StratusWeight,     TargetState.StratusWeight,     t);
		CurrentState.NimboWeight       = Mathf.Lerp(_startState.NimboWeight,       TargetState.NimboWeight,       t);

		CurrentState.RainIntensity = Mathf.Lerp(_startState.RainIntensity, TargetState.RainIntensity, t);
		CurrentState.DrizzleBlend  = Mathf.Lerp(_startState.DrizzleBlend,  TargetState.DrizzleBlend,  t);
		CurrentState.SnowIntensity = Mathf.Lerp(_startState.SnowIntensity, TargetState.SnowIntensity, t);
	}
}
