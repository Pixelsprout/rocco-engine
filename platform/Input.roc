import Vocabulary

# The Input a test gives step. The host builds the real one.
Input := [].{
	empty : Vocabulary.Input
	empty = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }
}

expect Input.empty == { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }
