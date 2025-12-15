### Flamethrower rehabilitation

tl;dr

This plugin addressess the issues with the flamethrower that were pointed out in this video: https://www.youtube.com/watch?v=JqaI5LhNalk

1. Disables Blue Moon rampup mechanics.
2. Reverses flame priority for dealing damage (damage is now based on youngest possible flame instead of oldest).
3. Introduces new heuristics for estimating flames density (which was the goal of the Blue Moon rampup mechanics) which is based on player's angular speed estimation.

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

How heuristics works: whenever a flame is picked for damage, the game looks back into history and estimates angular speed of the player at the time when the flame was spawned. If angular speed is estimated to be greater than certain threshold, then the flame is considered to represent sparse state of fire thus it is penalized with damage reduction proportional to the amount of angular speed (up until second threshold value where the damage reduction ends and is capped at -50%).

The default numbers were tuned such that it is expected that almost 100% of the time there is no damage penalty whatsoever so long the player doesn't try to cover a large volume with fire intentionally (which is precisely the tactics that Valve TRIED to address with the Blue Moon mechanics). In other words, spin around like crazy, and the maximum penalty is applied by guarantee; focus static target and expect no penalty by guarantee; play like normal and almost never face the penalty except, maybe, for occasional tiny fractions of a second when you change your view direction to switch targets and unintentionally get a trade-off of having a larger volume covered with sparser, less-damaging, flames.

Or, even shorter, this is what Valve intended to introduce but it also works.

Tested on Windows.

```
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
"sm_ftrehab_display_angular_speed_multiplier" = "0" min. 0.000000 max. 1.000000
 - (For development) If enabled, damage multiplier that is based on angular speed will be displayed to the player
```

### Demonstration

https://www.youtube.com/watch?v=xsNfgdueT9U
