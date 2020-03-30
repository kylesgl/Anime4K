//Anime4K v2.0RC5_CAS + v2.1a_Denoise

//!DESC Anime4K-Hybrid-CAS-v2.0RC5
//!HOOK LUMA
//!BIND HOOKED

/* ---------------------- CAS SETTINGS ---------------------- */

//CAS Sharpness, initial sharpen filter strength (traditional sharpening)
#define SHARPNESS 1.5

/* --- MOST OF THE OTHER SETTINGS CAN BE FOUND AT THE END --- */

float lerp(float x, float y, float a) {
	return mix(x, y, a);
}

float saturate(float x) {
	return clamp(x, 0, 1);
}

float minf3(float x, float y, float z) {
	return min(x, min(y, z));
}

float maxf3(float x, float y, float z) {
	return max(x, max(y, z));
}

float rcp(float x) {
	if (x < 0.000001) {
		x = 0.000001;
	}
	return 1.0 / x;
}

vec4 hook() {	 
	float sharpval = clamp(LUMA_size.x / 3840, 0, 1) * SHARPNESS;
	
	// fetch a 3x3 neighborhood around the pixel 'e',
	//	a b c
	//	d(e)f
	//	g h i
	
	float pixelX = HOOKED_pt.x;
	float pixelY = HOOKED_pt.y;
	float a = HOOKED_tex(HOOKED_pos + vec2(-pixelX, -pixelY)).x;
	float b = HOOKED_tex(HOOKED_pos + vec2(0.0, -pixelY)).x;
	float c = HOOKED_tex(HOOKED_pos + vec2(pixelX, -pixelY)).x;
	float d = HOOKED_tex(HOOKED_pos + vec2(-pixelX, 0.0)).x;
	float e = HOOKED_tex(HOOKED_pos).x;
	float f = HOOKED_tex(HOOKED_pos + vec2(pixelX, 0.0)).x;
	float g = HOOKED_tex(HOOKED_pos + vec2(-pixelX, pixelY)).x;
	float h = HOOKED_tex(HOOKED_pos + vec2(0.0, pixelY)).x;
	float i = HOOKED_tex(HOOKED_pos + vec2(pixelX, pixelY)).x;
  
	// Soft min and max.
	//	a b c			  b
	//	d e f * 0.5	 +	d e f * 0.5
	//	g h i			  h
	// These are 2.0x bigger (factored out the extra multiply).
	
	float mnR = minf3( minf3(d, e, f), b, h);
	
	float mnR2 = minf3( minf3(mnR, a, c), g, i);
	mnR = mnR + mnR2;
	
	float mxR = maxf3( maxf3(d, e, f), b, h);
	
	float mxR2 = maxf3( maxf3(mxR, a, c), g, i);
	mxR = mxR + mxR2;
	
	// Smooth minimum distance to signal limit divided by smooth max.
	float rcpMR = rcp(mxR);

	float ampR = saturate(min(mnR, 2.0 - mxR) * rcpMR);
	
	// Shaping amount of sharpening.
	ampR = sqrt(ampR);
	
	// Filter shape.
	//  0 w 0
	//  w 1 w
	//  0 w 0  
	float peak = -rcp(lerp(8.0, 5.0, saturate(sharpval)));

	float wR = ampR * peak;

	float rcpWeightR = rcp(1.0 + 4.0 * wR);

	vec4 outColor = vec4(saturate((b*wR+d*wR+f*wR+h*wR+e)*rcpWeightR), 0, 0, 0);
	return outColor;
}


//!DESC Anime4K-Hybrid-Luma-Denoise-v2.1a
//!HOOK LUMA
//!BIND HOOKED

/* ---------------------- BILATERAL MODE FILTERING SETTINGS ---------------------- */

#define STRENGTH 0.1
#define SPREAD_STRENGTH 2.0
#define MODE_REGULARIZATION 50.0

/* --- MOST OF THE OTHER SETTINGS CAN BE FOUND AT THE END --- */

#define KERNELSIZE 3
#define KERNELHALFSIZE 1
#define KERNELLEN 9

#define GETOFFSET(i) vec2((i % KERNELSIZE) - KERNELHALFSIZE, (i / KERNELSIZE) - KERNELHALFSIZE)

float gaussian(float x, float s, float m) {
	return (1 / (s * sqrt(2 * 3.14159))) * exp(-0.5 * pow(abs(x - m) / s, 2.0));
}

vec4 getMode(vec4 histogram_v[KERNELLEN], float histogram_w[KERNELLEN]) {
	vec4 maxv = vec4(0);
	float maxw = 0;
	
	for (int i=0; i<KERNELLEN; i++) {
		if (histogram_w[i] > maxw) {
			maxw = histogram_w[i];
			maxv = histogram_v[i];
		}
	}
	
	return maxv;
}

vec4 hook() {
	vec2 d = HOOKED_pt;
	
	float sharpval = clamp(HOOKED_size.x / 1920, 0, 1);
	
	vec4 histogram_v[KERNELLEN];
	float histogram_w[KERNELLEN];
	float histogram_wn[KERNELLEN];
	
	float vc = HOOKED_tex(HOOKED_pos).x;
	
	float s = vc * STRENGTH + 0.0001;
	float ss = SPREAD_STRENGTH * sharpval + 0.0001;
	
	for (int i=0; i<KERNELLEN; i++) {
		vec2 ipos = GETOFFSET(i);
		histogram_v[i] = HOOKED_tex(HOOKED_pos + ipos * d);
		histogram_w[i] = gaussian(vc - histogram_v[i].x, s, 0) * gaussian(distance(vec2(0), ipos), ss, 0);
		histogram_wn[i] = 0;
	}
	
	float sr = MODE_REGULARIZATION / 255.0;
	
	for (int i=0; i<KERNELLEN; i++) {
		for (int j=0; j<KERNELLEN; j++) {
			histogram_wn[j] += gaussian(histogram_v[j].x, sr, histogram_v[i].x) * histogram_w[i];
		}
	}
	
	return vec4(getMode(histogram_v, histogram_wn).x, 0, 0, 0);
}