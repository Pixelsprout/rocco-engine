import Vocabulary

## Builds the Pose of a Draw and wraps the time of a Clip that repeats.
Pose := [].{

	## The Pose that plays `clip` at `time`, with no fade. `Pose.still(0, 0.0)`
	## draws the bind pose.
	still : U32, F32 -> Vocabulary.Pose
	still = |clip, time| { clip, time, fade_clip: 0, fade_time: 0.0, fade: 0.0 }

	## Wraps `time` into the range from 0 up to `duration`, so a Clip repeats.
	## A time below 0 wraps from the end. A `duration` of 0 or less gives 0.
	## Keep the raw time in your Model and wrap it in `view`, or wrap it each
	## step so it stays small.
	loop : F32, F32 -> F32
	loop = |time, duration|
		if duration <= 0.0 {
			0.0
		} else {
			wrapped = time - duration * time.div_floor_by(duration)
			if wrapped < 0.0 or wrapped >= duration 0.0 else wrapped
		}
}

near : F32, F32 -> Bool
near = |a, b| (a - b).abs() < 0.0001

expect Pose.still(3, 0.5) == { clip: 3, time: 0.5, fade_clip: 0, fade_time: 0.0, fade: 0.0 }
expect Pose.still(0, 0.0) == { clip: 0, time: 0.0, fade_clip: 0, fade_time: 0.0, fade: 0.0 }

expect near(Pose.loop(0.25, 1.0), 0.25)
expect near(Pose.loop(2.5, 2.0), 0.5)
expect near(Pose.loop(4.0, 2.0), 0.0)
expect near(Pose.loop(-0.25, 1.0), 0.75)
expect Pose.loop(1.5, 0.0) == 0.0
expect Pose.loop(1.5, -1.0) == 0.0
