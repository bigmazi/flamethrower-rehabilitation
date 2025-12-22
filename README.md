### Flamethrower rehabilitation

tl;dr

This plugin addressess the issues with the flamethrower that were pointed out in this video: https://www.youtube.com/watch?v=JqaI5LhNalk

1. Disables Blue Moon rampup mechanics.
2. Reverses flame priority for dealing damage (damage is now based on youngest possible flame instead of oldest).
3. Introduces new heuristics for estimating flames density (which was the goal of the Blue Moon rampup mechanics) which is based on player's angular speed estimation.
4. (Since v1.1.0.0). Applies custom damage rampup that is independent from per-tick and per-touch logic.

More details: https://forums.alliedmods.net/showthread.php?p=2841241

---

### Problem

As I've shown in my "Meet the Broken Flamethrower" video (https://www.youtube.com/watch?v=JqaI5LhNalk) years ago, the flamethrower is clearly malfunctioning which is manifested through constant and unpredictable damage drops that players have no way to control and which provide no visual cues for why they happen (even in a slowed-down replay).

Basically, all the symptoms are caused by 2 root reasons:
1. The heuristics for detecting low-density flames (a.k.a. Blue Moon rampup) is poorly designed and in fact does not correlate to density very well. It is especially noticeable at close range where focused fire (even against static targets) still results in massive damage penalty.
2. The damage is decided by the oldest flame in contact. It is especially noticeable in enclosed areas and near walls where, due to this fact, all the work is done by the least damaging flames causing massive damage drops.

The most demonstrative part about it is that what used to be seen as a mathematically optimal circumstance for flamethrower, that is, burning targets who were entrapped in a corner at point-blank, suddenly became a scenario where players are almost guaranteed to get the harshest damage penalty: four times less damage.

### What this plugin does

This plugin addresses the issues that were pointed out in the video.
1. The priority of the flames is flipped: that is, the damage is now based on the youngest flame in contact.
2. The so-called Blue Moon rampup is disabled.
3. A new heuristics for detecting low-density flames (that was the goal of that Blue Moon rampup) is introduced. It is based on angular speed estimation of the flamethrower user.
4. (Since v1.1.0.0). Applies custom damage rampup that is independent from per-tick and per-touch logic.

### How density estimation heuristics works

Whenever a flame is picked for damage, the game looks back into history and estimates angular speed of the player at the time when the flame was spawned. If angular speed is estimated to be greater than certain threshold, then the flame is considered to represent sparse state of fire thus it is penalized with damage reduction proportional to the amount of angular speed (up until second threshold value where the damage reduction ends and is capped at -50%).

The default numbers were tuned such that it is expected that almost 100% of the time there is no damage penalty whatsoever so long the player doesn't try to cover a large volume with fire intentionally (which is precisely the tactics that Valve TRIED to address with the Blue Moon mechanics). In other words, spin around like crazy, and the maximum penalty is applied by guarantee; focus static target and expect no penalty by guarantee; play like normal and almost never face the penalty except, maybe, for occasional tiny fractions of a second when you change your view direction to switch targets and unintentionally get a trade-off of having a larger volume covered with sparser, less-damaging, flames.

Or, even shorter, this is what Valve intended to introduce but it also works.

### How custom damage rampup works *(Since v1.1.0.0)*

Each time game decides to deal damage, custom rampup may be factored in. The game picks the minimum between two factors (density-based and rampup-based) and applies only one of them. Custom rampup factor scales from 50% (no rampup) to 100% (full rampup). Just like Blue Moon system (and unlike density estimation system), this custom rampup is a per attacker-victim pair value. Each time a particular victim is damaged, the rampup amount for the particular attacker vs this particular victim is incremented by specified amount (controlled by a cvar). Damage is dealt first, increment is done afterwards. Once damage is dealt, rampup amount lingers for specified duration (controlled by a cvar). Each hit refreshes this linger time. Once linger duration is over, rampup amount starts being drained at specified rate (controlled by a cvar).

The default values were tuned to match least possible time it takes to achieve full Blue Moon rampup. Those values were found empirically, which was actually not trivial due to how inconsistent Blue Moon system is (sometimes it will never hit 100%, sometimes it will never leave 50%, sometimes it loops between values, sometimes it takes seconds, sometimes it takes a fraction of second, sensible to view direction, sensible to attack angle, sensible to tickrate, sensible to current time, sensible to distance, SCREW IT!!!).

```
"sm_ftrehab_plugin_enabled" = "1" min. 0.000000 max. 1.000000
 - Enables the effect of "Flamethrower Rehabilitation" plugin
"sm_ftrehab_reverse_flames_priority" = "1" min. 0.000000 max. 1.000000
 - If enabled, reverses flames priority (i.e. the damage will be based on the youngest possible flame)
"sm_ftrehab_bluemoon_rampup" = "0" min. 0.000000 max. 1.000000
 - 0 = Disable Blue Moon rampup, 1 = Keep it as is
"sm_ftrehab_angular_speed_affects_damage" = "1" min. 0.000000 max. 1.000000
 - If enabled, player's angular speed affects flamethrower damage
"sm_ftrehab_angular_speed_estimation_time_window" = "0.35" min. 0.100000 max. 5.000000
 - Look THIS far back (in seconds) into history for angular speed estimation
"sm_ftrehab_angular_speed_estimation_depth" = "20" min. 1.000000 max. 500.000000
 - Use THIS many frames at most for angular speed estimation
"sm_ftrehab_angular_speed_start_penalty" = "400" min. 0.000000
 - There will be no damage penalty so long the angular speed is estimated to be lower than THIS value (deg/s)
"sm_ftrehab_angular_speed_end_penalty" = "900" min. 0.000000
 - The damage penalty is at maximum whenever the angular speed is estimated to be greater than THIS value (deg/s)
"sm_ftrehab_custom_rampup_enabled" = "1" min. 0.000000 max. 1.000000
 - Enables custom damage rampup
"sm_ftrehab_custom_rampup_increment_per_hit" = "0.15" min. 0.000000
 - Amount of rampup gain per hit (from 0.0 to 1.0 where these numbers represent min and max damage respectively)
"sm_ftrehab_custom_rampup_linger_time" = "0.2" min. 0.000000
 - When not refreshed, rampup won't be drained for THIS many seconds
"sm_ftrehab_custom_rampup_drain_time" = "0.5" min. 0.001000
 - It takes THIS many seconds to drain rampup from max to min
"sm_ftrehab_custom_rampup_first_tick_deals_max_damage" = "0" min. 0.000000 max. 1.000000
 - If rampup amount is exactly at minimum, maximum damage will be dealt (this is how the weapon behaves in unmodified game!)
"sm_ftrehab_custom_rampup_increment_is_affected_by_angular_speed" = "1" min. 0.000000 max. 1.000000
 - Custom rampup increment should be multiplied by angular speed damage factor
"sm_ftrehab_display_angular_speed_multiplier" = "0" min. 0.000000 max. 1.000000
 - (For development) If enabled, damage multiplier that is based on angular speed will be displayed to the player
"sm_ftrehab_display_custom_rampup" = "0" min. 0.000000 max. 1.000000
 - (For development) If enabled, damage multiplier that is based on custom rampup will be displayed to the player
"sm_ftrehab_refill_dummy_bots" = "0" min. 0.000000 max. 1.000000
 - (For development) Whenever damage computations are made, "bot_refill" is executed
```

### Demonstration

https://www.youtube.com/watch?v=xsNfgdueT9U
