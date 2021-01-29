import fcore

const screenspace = """
attribute vec4 a_position;
attribute vec2 a_texc; 
varying vec2 v_texc;

void main(){
	v_texc = a_texc;
	gl_Position = a_position;
}
"""

type Bloom = object
  buffer, p1, p2: Framebuffer
  thresh, bloom, blur: Shader
  blurPasses*: int

proc newBloom(): Bloom =
  result.buffer = newFramebuffer()
  result.p1 = newFramebuffer()
  result.p2 = newFramebuffer()
  result.blurPasses = 1

  result.thresh = newShader(screenspace,
  """ 
  uniform lowp sampler2D u_texture0;
  uniform lowp vec2 threshold;
  varying vec2 v_texc;

  void main(){
    vec4 color = texture2D(u_texture0, v_texc);
    if(color.r + color.g + color.b > 0.5 * 3.0){
      gl_FragColor = color;
    }else{
      gl_FragColor = vec4(0.0);
    }
  }
  """
  )

  result.bloom = newShader(screenspace,
  """ 
  uniform lowp sampler2D u_texture0;
  uniform lowp sampler2D u_texture1;
  uniform lowp float u_bloomIntensity;
  uniform lowp float u_originalIntensity;

  varying vec2 v_texc;

  void main(){
    vec4 original = texture2D(u_texture0, v_texc) * u_bloomIntensity;
    vec4 bloom = texture2D(u_texture1, v_texc) * u_originalIntensity; 	
      original = original *  (vec4(1.0) - bloom);	 	
    gl_FragColor =  original + bloom; 	
  }

  """
  )

  result.blur = newShader(
  """ 
  attribute vec4 a_position;
  attribute vec2 a_texc; 
  uniform vec2 dir;
  uniform vec2 size;
  varying vec2 v_texCoords0;
  varying vec2 v_texCoords1;
  varying vec2 v_texCoords2;
  varying vec2 v_texCoords3;
  varying vec2 v_texCoords4;
  const vec2 futher = vec2(3.2307692308, 3.2307692308);
  const vec2 closer = vec2(1.3846153846, 1.3846153846);

  void main(){
    vec2 sizeAndDir = dir / size;
    vec2 f = futher*sizeAndDir;
    vec2 c = closer*sizeAndDir;
    
    v_texCoords0 = a_texc - f;
    v_texCoords1 = a_texc - c;	
    v_texCoords2 = a_texc;
    v_texCoords3 = a_texc + c;
    v_texCoords4 = a_texc + f;
    
    gl_Position = a_position;
  }
  """,
  """ 
  uniform lowp sampler2D u_texture;
  varying vec2 v_texCoords0;
  varying vec2 v_texCoords1;
  varying vec2 v_texCoords2;
  varying vec2 v_texCoords3;
  varying vec2 v_texCoords4;
  const float center = 0.2270270270; 
  const float close = 0.3162162162;
  const float far = 0.0702702703;

  void main(){
    gl_FragColor = far * texture2D(u_texture, v_texCoords0) 
          + close * texture2D(u_texture, v_texCoords1)
          + center * texture2D(u_texture, v_texCoords2) 
          + close * texture2D(u_texture, v_texCoords3)
          + far * texture2D(u_texture, v_texCoords4); 
  }	
  """
  )

proc capture*(bloom: Bloom) =
  bloom.buffer.push(colorClear)

proc render*(bloom: Bloom) =
  bloom.buffer.pop()

  bloom.p1.push()
  bloom.buffer.blitQuad(bloom.thresh)
  bloom.p1.pop()

  for i in 0..<bloom.blurPasses:
    #horizontal
    bloom.p2.push()
    bloom.blur.setf("dir", 1, 0)
    bloom.p1.blitQuad(bloom.blur)
    bloom.p2.pop()

    #vertical
    bloom.p1.push()
    bloom.blur.setf("dir", 0, 1)
    bloom.p2.blitQuad(bloom.blur)
    bloom.p1.pop()

  bloom.p1.texture.use(1)
  bloom.buffer.blitQuad(bloom.bloom)