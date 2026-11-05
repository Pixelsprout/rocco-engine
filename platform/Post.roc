import Shader
import Vocabulary

## Ordered world effects. UI draws after every effect.
Post := [].{

	## Run a generated Draw-scope value record in linear HDR before bloom.
	before_bloom : Shader.Values -> Vocabulary.Post
	before_bloom = |values| { values, location: BeforeBloom, enabled: Bool.True }

	## Run a generated Draw-scope value record in display colour before UI.
	after_tone_map : Shader.Values -> Vocabulary.Post
	after_tone_map = |values| { values, location: AfterToneMap, enabled: Bool.True }
}
