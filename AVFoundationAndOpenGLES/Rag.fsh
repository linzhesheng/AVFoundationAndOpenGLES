precision mediump float;
varying highp vec2 texCoordVarying;
uniform sampler2D SamplerY;
uniform sampler2D SamplerUV;
uniform mat3 colorConversionMatrix;

uniform float Time;

const float PI = 3.1415926;

float rand(float n) {
    return fract(sin(n) * 43758.5453123);
}

vec4 getRgba(vec2 texCoordVary) {
    mediump vec3 yuv;
    lowp vec3 rgb;
    yuv.x = (texture2D(SamplerY, texCoordVary).r - (16.0/255.0));
    yuv.yz = (texture2D(SamplerUV, texCoordVary).rg - vec2(0.5, 0.5));
    rgb = colorConversionMatrix * yuv;
    return vec4(rgb, 1);
}

void main () {
    float maxJitter = 0.06;
    float duration = 0.3;
    float colorROffset = 0.01;
    float colorBOffset = -0.025;
    
    float time = mod(Time, duration * 2.0);
    float amplitude = max(sin(time * (PI / duration)), 0.0);
    
    float jitter = rand(texCoordVarying.y) * 2.0 - 1.0; // -1~1
    bool needOffset = abs(jitter) < maxJitter * amplitude;
    
    float textureX = texCoordVarying.x + (needOffset ? jitter : (jitter * amplitude * 0.006));
    vec2 textureCoords = vec2(textureX, texCoordVarying.y);
    
    vec4 mask = getRgba(textureCoords);
    vec4 maskR = getRgba(textureCoords + vec2(colorROffset * amplitude, 0.0));
    vec4 maskB = getRgba(textureCoords + vec2(colorBOffset * amplitude, 0.0));
    
    gl_FragColor = vec4(maskR.r, mask.g, maskB.b, mask.a);
}
