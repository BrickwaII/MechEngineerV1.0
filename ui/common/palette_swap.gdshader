shader_type canvas_item;
// Recolors pixel-art sprites: every texel that matches a key color becomes the
// matching target color. Ally parts are drawn in key colors (see
// data/feel/sprite_manifest.json "key_colors") so each bot gets its own
// palette. `flash` mixes toward flash_color for hit flashes.

const int MAX_KEYS = 8;

uniform vec4 keys[MAX_KEYS];
uniform vec4 targets[MAX_KEYS];
uniform int key_count = 0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	for (int i = 0; i < MAX_KEYS; i++) {
		if (i < key_count && distance(c.rgb, keys[i].rgb) < 0.02) {
			c.rgb = targets[i].rgb;
		}
	}
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	COLOR = c * tint;
}
