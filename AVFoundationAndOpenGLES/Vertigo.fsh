precision mediump float;
varying highp vec2 texCoordVarying;
uniform sampler2D SamplerY;
uniform sampler2D SamplerUV;
uniform mat3 colorConversionMatrix;

uniform float Time;

const float PI = 3.1415926;
const float duration = 2.0;

vec4 getRgba(vec2 texCoordVarying) {
    mediump vec3 yuv;
    lowp vec3 rgb;
    yuv.x = (texture2D(SamplerY, texCoordVarying).r - (16.0/255.0));
    yuv.yz = (texture2D(SamplerUV, texCoordVarying).rg - vec2(0.5, 0.5));
    rgb = colorConversionMatrix * yuv;
    return vec4(rgb, 1);
}

vec4 getMask(float time, vec2 textureCoords, float padding) {
    vec2 translation = vec2(sin(time * (PI * 2.0 / duration)), cos(time * (PI * 2.0 / duration)));
    vec2 translationTextureCoords = textureCoords + padding * translation;
    vec4 mask = getRgba(translationTextureCoords);
    
    return mask;
}

float maskAlphaProgress(float currentTime, float hideTime, float startTime) {
    float time = mod(duration + currentTime - startTime, duration);
    return min(time, hideTime);
}

void main()
{
    float time = mod(Time, duration);
    float scale = 1.2;
    float padding = 0.5 * (1.0 - 1.0 / scale);
    vec2 textureCoords = vec2(0.5, 0.5) + (texCoordVarying - vec2(0.5, 0.5)) / scale;
    
    float hideTime = 0.9;
    float timeGap = 0.2;
    
    float maxAlphaR = 0.5; // max R
    float maxAlphaG = 0.05; // max G
    float maxAlphaB = 0.05; // max B
    
    vec4 mask = getMask(time, textureCoords, padding);
    float alphaR = 1.0; // R
    float alphaG = 1.0; // G
    float alphaB = 1.0; // B
    
    vec4 resultMask = vec4(0, 0, 0, 0);
    for (float f = 0.0; f < duration; f += timeGap) {
        float tmpTime = f;
        vec4 tmpMask = getMask(tmpTime, textureCoords, padding);
        
        //
        float tmpAlphaR = maxAlphaR - maxAlphaR * maskAlphaProgress(time, hideTime, tmpTime) / hideTime;
        float tmpAlphaG = maxAlphaG - maxAlphaG * maskAlphaProgress(time, hideTime, tmpTime) / hideTime;
        float tmpAlphaB = maxAlphaB - maxAlphaB * maskAlphaProgress(time, hideTime, tmpTime) / hideTime;
     
        resultMask += vec4(tmpMask.r * tmpAlphaR,
                           tmpMask.g * tmpAlphaG,
                           tmpMask.b * tmpAlphaB,
                           1.0);
        alphaR -= tmpAlphaR;
        alphaG -= tmpAlphaG;
        alphaB -= tmpAlphaB;
    }
    resultMask += vec4(mask.r * alphaR, mask.g * alphaG, mask.b * alphaB, 1.0);
    
    vec4 rgba = getRgba(texCoordVarying);
    gl_FragColor = resultMask;
}

