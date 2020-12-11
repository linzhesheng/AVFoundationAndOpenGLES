attribute vec4 position;
attribute vec2 texCoord;
varying vec2 texCoordVarying;
void main()
{
    texCoordVarying = texCoord;
    gl_Position = position;
}
