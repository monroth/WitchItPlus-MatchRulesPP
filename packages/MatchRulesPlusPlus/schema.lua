-- Native rule schema (cooked UIParameters) and Match Rules + extra rules. Data only.
local M={}
M.groups = {
  {category="match",id=1,property="GlobalMatchParameters",rows={
    {name="GlobalGravity",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="EnableBuffDrops",kind="bool",min=0,max=0,factor=1,step=0},
    {name="EnableWardrobe",kind="bool",min=0,max=0,factor=1,step=0}
}},
  {category="match",id=2,property="HunterMatchParameters",rows={
    {name="StaminaEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="CooldownMultiplier",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="MovementSpeedMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="JumpHeightMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="PlayerSizeMultiplier",kind="float",min=0.10000000149011612,max=2.0,factor=1,step=0.10000000149011612},
    {name="DamageMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="VoicePitch",kind="float",min=0,max=2.0,factor=1,step=0.10000000149011612}
}},
  {category="match",id=3,property="WitchMatchParameters",rows={
    {name="CooldownMultiplier",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="MaxHealthMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="MaxManaMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="ManaRegenMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="MovementSpeedMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="JumpHeightMultiplier",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="PlayerSizeMultiplier",kind="float",min=0.10000000149011612,max=2.0,factor=1,step=0.10000000149011612},
    {name="VoicePitch",kind="float",min=0,max=2.0,factor=1,step=0.10000000149011612}
}},
  {category="skills",id=1,property="Chicken",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="InitialVelocity",kind="float",min=0,max=5000.0,factor=0.009999999776482582,step=5.0},
    {name="VelocityAfterLanding",kind="float",min=0,max=5000.0,factor=0.009999999776482582,step=5.0},
    {name="CheckRadius",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=1.0},
    {name="Duration",kind="float",min=0,max=40.0,factor=1,step=0.5},
    {name="Scale",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="Pitch",kind="float",min=0,max=2.0,factor=1,step=0.10000000149011612}
}},
  {category="skills",id=2,property="Hook",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="Damage",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="HookVelocity",kind="float",min=1.0,max=10000.0,factor=0.009999999776482582,step=10.0},
    {name="HookDuration",kind="float",min=0,max=10.0,factor=1,step=0.25},
    {name="PullStrength",kind="float",min=1.0,max=5000.0,factor=0.009999999776482582,step=10.0},
    {name="PullDuration",kind="float",min=0,max=10.0,factor=1,step=0.25}
}},
  {category="skills",id=3,property="Cannonball",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="PassiveJump",kind="float",min=10.0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="AirControl",kind="float",min=0,max=1.0,factor=1,step=0.10000000149011612},
    {name="GravityScale",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="ImpactSizeSmall",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=25.0},
    {name="ImpactSizeMedium",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=25.0},
    {name="ImpactSizeBig",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=25.0},
    {name="ImpactForceSmall",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="ImpactForceMedium",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="ImpactForceBig",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="ImpactDamageSmall",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ImpactDamageMedium",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ImpactDamageBig",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ShockwaveSizeSmall",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=25.0},
    {name="ShockwaveSizeMedium",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=25.0},
    {name="ShockwaveSizeBig",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=25.0},
    {name="ShockwaveForceSmall",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="ShockwaveForceMedium",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="ShockwaveForceBig",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0}
}},
  {category="skills",id=4,property="Garlic",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="Velocity",kind="float",min=0,max=10000.0,factor=0.009999999776482582,step=10.0},
    {name="Radius",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=25.0},
    {name="Duration",kind="float",min=0,max=20.0,factor=1,step=0.25}
}},
  {category="skills",id=5,property="Trap",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="SuckDuration",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="SlowTime",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="WitchVacuumRadius",kind="float",min=0,max=1000.0,factor=0.009999999776482582,step=10.0},
    {name="PropVacuumRadius",kind="float",min=0,max=1000.0,factor=0.009999999776482582,step=10.0},
    {name="PullForceWitch",kind="float",min=0,max=40.0,factor=1,step=0.5},
    {name="PullForceProp",kind="float",min=0,max=40.0,factor=1,step=0.5}
}},
  {category="skills",id=6,property="PowerBall",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="Damage",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="MaxSpeed",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="Acceleration",kind="float",min=0,max=5000.0,factor=0.009999999776482582,step=50.0},
    {name="CanJumpDelay",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="JumpForce",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="FallAcceleration",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0}
}},
  {category="skills",id=7,property="Decoy",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="ActivationManaCost",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ManaCostPerSecond",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="DecoyHealth",kind="float",min=1.0,max=100.0,factor=1,step=1.0}
}},
  {category="skills",id=8,property="Mushroom",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="ActivationManaCost",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ProjectileVelocity",kind="float",min=0,max=4000.0,factor=0.009999999776482582,step=10.0},
    {name="SplitProjectileVelocity",kind="float",min=0,max=4000.0,factor=0.009999999776482582,step=10.0},
    {name="SplitIterations",kind="int",min=0,max=3.0,factor=1,step=1.0},
    {name="SplitCount",kind="int",min=0,max=5.0,factor=1,step=1.0},
    {name="ConfuseDuration",kind="float",min=0,max=10.0,factor=1,step=0.25},
    {name="MushroomDuration",kind="float",min=1.0,max=20.0,factor=1,step=0.25},
    {name="EffectRadius",kind="float",min=0,max=1000.0,factor=0.009999999776482582,step=25.0},
    {name="MushroomSize",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="MiniMushroomSize",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612}
}},
  {category="skills",id=9,property="Fly",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="ActivationManaCost",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ManaCostPerSecond",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ForceMultiplier",kind="float",min=0.10000000149011612,max=5.0,factor=1,step=0.10000000149011612}
}},
  {category="skills",id=10,property="JumpScare",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="ActivationManaCost",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="StartVelocity",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="Acceleration",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="ScalePerSecond",kind="float",min=0,max=50.0,factor=1,step=0.5},
    {name="BlindDurationMinimum",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="BlindDurationMaximum",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="FlightDuration",kind="float",min=0,max=20.0,factor=1,step=0.25}
}},
  {category="skills",id=11,property="Possess",rows={
    {name="IsLIsted",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="ActivationManaCost",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="Range",kind="float",min=0,max=10000.0,factor=0.009999999776482582,step=50.0}
}},
  {category="skills",id=12,property="FlyingEye",rows={
    {name="IsLIsted",kind="bool",min=0,max=0,factor=1,step=0},
    {name="ActivationManaCost",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ManaCostPerSecond",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="MaxSpeed",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="Acceleration",kind="float",min=0,max=10000.0,factor=0.009999999776482582,step=100.0},
    {name="Deceleration",kind="float",min=0,max=10000.0,factor=0.009999999776482582,step=100.0},
    {name="Scale",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612}
}},
  {category="skills",id=13,property="Potato",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=10.0,factor=1,step=0.10000000149011612},
    {name="ManualFireCooldown",kind="float",min=0.05000000074505806,max=10.0,factor=1,step=0.05000000074505806},
    {name="StaminaCost",kind="float",min=0,max=1.0,factor=1,step=0.009999999776482582},
    {name="Damage",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="Velocity",kind="float",min=0,max=15000.0,factor=0.009999999776482582,step=100.0},
    {name="GravityScale",kind="float",min=0,max=10.0,factor=1,step=0.10000000149011612},
    {name="PushStrength",kind="float",min=0,max=50.0,factor=1,step=0.5},
    {name="ProjectileHealth",kind="float",min=0,max=1.0,factor=1,step=0.05000000074505806},
    {name="ProjectileScale",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="Projectiles",kind="int",min=1.0,max=10.0,factor=1,step=1.0},
    {name="Spread",kind="float",min=0,max=90.0,factor=1,step=1.0}
}},
  {category="skills",id=14,property="Melee",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="ChargeTime",kind="float",min=0,max=5.0,factor=1,step=0.10000000149011612},
    {name="DamageUncharged",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="DamageCharged",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="ForceUncharged",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="ForceCharged",kind="float",min=0,max=3000.0,factor=0.009999999776482582,step=10.0},
    {name="DistanceUncharged",kind="float",min=0,max=10.0,factor=1,step=0.25},
    {name="DistanceCharged",kind="float",min=0,max=10.0,factor=1,step=0.25}
}},
  {category="skills",id=15,property="Train",rows={
    {name="IsListed",kind="bool",min=0,max=0,factor=1,step=0},
    {name="Cooldown",kind="float",min=0.05000000074505806,max=20.0,factor=1,step=0.10000000149011612},
    {name="Damage",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="Velocity",kind="float",min=0,max=5000.0,factor=0.009999999776482582,step=50.0},
    {name="GravityScale",kind="float",min=0,max=5.0,factor=1,step=0.10000000149011612},
    {name="Duration",kind="float",min=0,max=20.0,factor=1,step=0.25}
}},
  {category="powerups",id=1,property="HunterCooldownReduction",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="BuffLength",kind="float",min=1.0,max=60.0,factor=1,step=1.0},
    {name="CooldownMultiplier",kind="float",min=0,max=1.0,factor=1,step=0.009999999776482582}
}},
  {category="powerups",id=2,property="HunterRapidFire",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="BuffLength",kind="float",min=1.0,max=60.0,factor=1,step=1.0},
    {name="StaminaCostMultiplier",kind="float",min=0,max=1.0,factor=1,step=0.05000000074505806},
    {name="CooldownMultiplier",kind="float",min=0.10000000149011612,max=1.0,factor=1,step=0.009999999776482582}
}},
  {category="powerups",id=3,property="HunterSpeedBoost",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="BuffLength",kind="float",min=1.0,max=60.0,factor=1,step=1.0},
    {name="SpeedMultiplier",kind="float",min=1.0,max=3.0,factor=1,step=0.10000000149011612}
}},
  {category="powerups",id=4,property="HunterDetection",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="BuffLength",kind="float",min=1.0,max=60.0,factor=1,step=1.0},
    {name="Scale",kind="float",min=0.5,max=10.0,factor=1,step=0.10000000149011612},
    {name="CheckRadius",kind="float",min=10.0,max=2000.0,factor=0.009999999776482582,step=10.0},
    {name="Pitch",kind="float",min=0.5,max=2.0,factor=1,step=0.10000000149011612}
}},
  {category="powerups",id=5,property="WitchManaBoost",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="BuffLength",kind="float",min=1.0,max=60.0,factor=1,step=1.0},
    {name="ManaRegenMultiplicator",kind="float",min=1.0,max=20.0,factor=1,step=0.10000000149011612}
}},
  {category="powerups",id=6,property="WitchHeal",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="HealAmmount",kind="float",min=0,max=1.0,factor=1,step=0.05000000074505806},
    {name="OverHealReductionMultiplier",kind="float",min=0,max=1.0,factor=1,step=0.05000000074505806}
}},
  {category="powerups",id=7,property="WitchInvisible",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="BuffLength",kind="float",min=1.0,max=60.0,factor=1,step=1.0}
}},
  {category="powerups",id=8,property="WitchConfusionWave",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="ConfuseDuration",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="EffectRadius",kind="float",min=10.0,max=10000.0,factor=0.009999999776482582,step=10.0}
}},
  {category="mods",id=1,property="MoveOrDamage",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="DamagePerInterval",kind="float",min=0,max=100.0,factor=1,step=1.0},
    {name="IntervalBetweenDamages",kind="float",min=0.10000000149011612,max=10.0,factor=1,step=0.10000000149011612},
    {name="SecondsUntilDamageStarts",kind="float",min=0,max=20.0,factor=1,step=0.25},
    {name="VelocityToAvoidDamage",kind="float",min=0,max=1000.0,factor=0.009999999776482582,step=10.0},
    {name="SilentDamage",kind="bool",min=0,max=0,factor=1,step=0},
    {name="EnableTaunting",kind="bool",min=0,max=0,factor=1,step=0}
}},
  {category="mods",id=2,property="DissolvingProps",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="IntervalBetweenDissolves",kind="float",min=5.0,max=500.0,factor=1,step=5.0},
    {name="PercentageOfPropsDissolved",kind="float",min=0.009999999776482582,max=1.0,factor=100.0,step=0.009999999776482582},
    {name="NumberOfIntervals",kind="int",min=0,max=10.0,factor=1,step=1.0}
}},
  {category="mods",id=3,property="PropRetaliation",rows={
    {name="IsEnabled",kind="bool",min=0,max=0,factor=1,step=0},
    {name="SingleTargetReflectionRatio",kind="float",min=0,max=5.0,factor=1,step=0.05000000074505806},
    {name="AreaDamageReflectionRatio",kind="float",min=0,max=5.0,factor=1,step=0.05000000074505806}
}}
}
M.collections = {
    match = {field='MatchRules', type='MatchRuleType_2_7A33ED664F8C0FBEE1C782B8057AEA07', params='UIParameters_6_D7D219FA47CFCDF8FCA3DB9DBCF39E11', rep=34},
    skills = {field='SkillRules', type='SkillType_2_5808B66B468AC4EC8E4F7096273ED505', params='SkillParameters_6_41DDEB6C424E37EF4C61239795AF12B0', setter='AddSkillRule', rep=32},
    mods = {field='GameModifiers', type='ModifierType_2_FEC4E34148D09164EA058CBDDCBE4C7F', params='UIParameters_6_270A78AB4625673AD2C87194A200889D', setter='AddGameModifier', rep=35},
    powerups = {field='PowerupRules', type='PowerupType_5_07F0F6FF44288141C9331F8C816DF5AF', params='PowerupParameters_6_855163784BFC03D7EC9FB8B8D2C10128', setter='AddPowerupRule', rep=37}
}
M.extras = {
    {key='pickupMin', label='Powerup spawn interval (s)', min=1, max=600, step=1, integer=true, initial=30, sliderMin=5, sliderMax=120},
    {key='pickupJitter', label='Powerup spawn variation (s)', min=0, max=600, step=1, integer=true, initial=10, sliderMin=0, sliderMax=60},
    {key='roundDelay', label='Time between rounds (s)', min=1, max=300, step=1, integer=true, initial=22, sliderMin=5, sliderMax=60},
    {key='potatoRecharge', label='Potato stamina recharge per second', min=0, max=1000, step=1, initial=10, sliderMin=0, sliderMax=50},
    {key='cooldownMin', label='Minimum cooldown (s)', min=.02, max=60, step=.02, initial=.02, sliderMin=0.02, sliderMax=5},
    {key='possessionLifetime', label='Abandoned prop lifetime (s)', min=.5, max=300, step=.5, initial=5, sliderMin=1, sliderMax=60},
    {key='propForce', label='Prop push strength multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='propAirForce', label='Prop push strength in air multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='propMaxSpeed', label='Prop speed limit multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='propJumpForce', label='Prop jump strength multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='propSpeed', label='Prop speed multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='propMass', label='Prop weight multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='hunterGravity', label='Hunter gravity multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='witchGravity', label='Witch gravity multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='padImpulse', label='Spring pad impulse multiplier', min=.05, max=10, step=.05, initial=1, sliderMin=0.05, sliderMax=3},
    {key='hunterAirControl', label='Hunter air control', min=0, max=1, step=.05, initial=.1},
    {key='witchAirControl', label='Witch air control', min=0, max=1, step=.05, initial=.1}
}
M.subsystems = {
    match='/Game/Blueprints/Match/GameRules/MatchRules/B_MatchParametersSubsystem.B_MatchParametersSubsystem_C',
    skills='/Game/Blueprints/Skills/B_SkillParametersSubsystem.B_SkillParametersSubsystem_C',
    mods='/Game/Blueprints/Match/GameRules/GameModifiers/B_ModParametersSubsystem.B_ModParametersSubsystem_C',
    powerups='/Game/Blueprints/Match/GameRules/PowerupRules/B_PowerupParametersSubsystem.B_PowerupParametersSubsystem_C'
}
return M
