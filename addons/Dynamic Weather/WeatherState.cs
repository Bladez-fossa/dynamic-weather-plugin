using Godot;
using System;


[GlobalClass]
public partial class WeatherState : Resource
{
	[Export] public float Humidity = 0.0f;
	[Export] public float CloudCoverage = 0.0f;
	[Export] public float Precipitation = 0.0f;
	[Export] public float WindSpeed = 0.0f;
	[Export] public float FogDensity = 0.0f;
	[Export] public float LightMultiplier = 1.0f;
	
  	[Export] public float CirrusWeight      = 0f;
	[Export] public float AltocumulusWeight = 0f;
	[Export] public float CumulusWeight     = 0f;
	[Export] public float StratusWeight     = 0f;
	[Export] public float NimboWeight       = 0f;
	
	[Export] public float RainIntensity = 0.0f;
	[Export] public float DrizzleBlend  = 0.0f;
	[Export] public float SnowIntensity = 0.0f;

	
}
