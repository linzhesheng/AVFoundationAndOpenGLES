precision mediump float;
varying highp vec2 texCoordVarying;
uniform sampler2D SamplerY;
uniform sampler2D SamplerUV;
uniform mat3 colorConversionMatrix;

uniform float Time;

vec4 getRgba(vec2 texCoordVarying) {
    mediump vec3 yuv;
    lowp vec3 rgb;
    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));
    yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5));
    rgb = colorConversionMatrix * yuv;
    return vec4(rgb, 1);
}


void main () {
    float duration = 0.7;
    float maxScale = 1.1;
    float offset = 0.02;
    
    float progress = mod(Time, duration) / duration; // 0~1
    vec2 offsetCoords = vec2(offset, offset) * progress;
    float scale = 1.0 + (maxScale - 1.0) * progress;
    
    vec2 ScaleTextureCoords = vec2(0.5, 0.5) + (texCoordVarying - vec2(0.5, 0.5)) / scale;
    
    vec4 maskR = getRgba(ScaleTextureCoords + offsetCoords);
    vec4 maskB = getRgba(ScaleTextureCoords - offsetCoords);
    vec4 mask = getRgba(ScaleTextureCoords);
    
    float alpha = 0.3;
    float alpha2 = 0.3;
    float alpha3 = 0.4;
    
    gl_FragColor = vec4(maskR.r, mask.g, maskB.b, mask.a);
}
