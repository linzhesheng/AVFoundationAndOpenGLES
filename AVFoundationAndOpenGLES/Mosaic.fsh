precision mediump float;
varying highp vec2 texCoordVarying;
uniform sampler2D SamplerY;
uniform sampler2D SamplerUV;
uniform mat3 colorConversionMatrix;

uniform float Time;

const vec2 TexSize = vec2(375.0, 667.0);
const vec2 mosaicSize = vec2(20.0, 20.0);
const float PI = 3.1415926;

vec4 getRgba(vec2 texCoordVarying) {
    mediump vec3 yuv;
    lowp vec3 rgb;
    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));
    yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5));
    rgb = colorConversionMatrix * yuv;
    return vec4(rgb, 1);
}


void main () {
    float duration = 3.0;
    float maxScale = 1.0;
    float time = mod(Time, duration);
    float progress = sin(time * (PI / duration));
    float scale = maxScale * progress;
    vec2 finSize = mosaicSize * scale;
    
    vec2 intXY = vec2(texCoordVarying.x*TexSize.x, texCoordVarying.y*TexSize.y);
    vec2 XYMosaic = vec2(floor(intXY.x/finSize.x)*finSize.x, floor(intXY.y/finSize.y)*finSize.y);
    vec2 UVMosaic = vec2(XYMosaic.x/TexSize.x, XYMosaic.y/TexSize.y);
    
    gl_FragColor = getRgba(UVMosaic);
}
