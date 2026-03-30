// Iridescent WebGL animated background
const vertexShaderSource = `
  attribute vec2 a_position;
  void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
  }
`;

const fragmentShaderSource = `
  precision mediump float;
  uniform float u_time;
  uniform vec2 u_resolution;
  uniform vec3 u_color;
  uniform float u_speed;
  uniform float u_amplitude;

  // Simplex-like noise
  vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
  vec3 permute(vec3 x) { return mod289(((x * 34.0) + 1.0) * x); }

  float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                       -0.577350269189626, 0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1;
    i1.x = step(x0.y, x0.x);
    i1.y = 1.0 - i1.x;
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
                             + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
                            dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
  }

  void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution;
    float t = u_time * u_speed;

    // Layered noise for organic movement
    float n1 = snoise(uv * 3.0 + t * 0.3) * u_amplitude;
    float n2 = snoise(uv * 5.0 - t * 0.2) * u_amplitude * 0.5;
    float n3 = snoise(uv * 8.0 + t * 0.15) * u_amplitude * 0.25;
    float noise = n1 + n2 + n3;

    // Iridescent color shift
    vec3 col1 = u_color;
    vec3 col2 = vec3(u_color.z, u_color.x, u_color.y);
    vec3 col3 = vec3(u_color.y, u_color.z, u_color.x);

    float angle = uv.x * 2.0 + uv.y + noise + t * 0.1;
    vec3 color = col1 * (0.5 + 0.5 * sin(angle))
               + col2 * (0.5 + 0.5 * sin(angle + 2.094))
               + col3 * (0.5 + 0.5 * sin(angle + 4.189));

    // Soft gradient overlay
    color *= 0.6 + 0.4 * smoothstep(0.0, 1.0, uv.y + noise * 0.3);

    // Subtle sparkle
    float sparkle = pow(max(0.0, snoise(uv * 20.0 + t)), 8.0) * 0.15;
    color += sparkle;

    gl_FragColor = vec4(color, 1.0);
  }
`;

function createShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    console.error("Shader compile error:", gl.getShaderInfoLog(shader));
    gl.deleteShader(shader);
    return null;
  }
  return shader;
}

export function initWebGL(canvas, color, speed, amplitude) {
  const gl = canvas.getContext("webgl", { alpha: false, antialias: false });
  if (!gl) {
    console.warn("WebGL not supported");
    return null;
  }

  const vertexShader = createShader(gl, gl.VERTEX_SHADER, vertexShaderSource);
  const fragmentShader = createShader(gl, gl.FRAGMENT_SHADER, fragmentShaderSource);

  const program = gl.createProgram();
  gl.attachShader(program, vertexShader);
  gl.attachShader(program, fragmentShader);
  gl.linkProgram(program);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.error("Program link error:", gl.getProgramInfoLog(program));
    return null;
  }

  gl.useProgram(program);

  // Full-screen quad
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
    -1, -1, 1, -1, -1, 1,
    -1, 1, 1, -1, 1, 1
  ]), gl.STATIC_DRAW);

  const posLoc = gl.getAttribLocation(program, "a_position");
  gl.enableVertexAttribArray(posLoc);
  gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);

  const uTime = gl.getUniformLocation(program, "u_time");
  const uResolution = gl.getUniformLocation(program, "u_resolution");
  const uColor = gl.getUniformLocation(program, "u_color");
  const uSpeed = gl.getUniformLocation(program, "u_speed");
  const uAmplitude = gl.getUniformLocation(program, "u_amplitude");

  gl.uniform3f(uColor, color[0], color[1], color[2]);
  gl.uniform1f(uSpeed, speed);
  gl.uniform1f(uAmplitude, amplitude);

  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth * dpr;
    const h = canvas.clientHeight * dpr;
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      gl.viewport(0, 0, w, h);
      gl.uniform2f(uResolution, w, h);
    }
  }

  let animId;
  const startTime = performance.now();

  function render() {
    resize();
    gl.uniform1f(uTime, (performance.now() - startTime) / 1000.0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    animId = requestAnimationFrame(render);
  }

  render();

  return {
    destroy() { cancelAnimationFrame(animId); },
    updateParams(newColor, newSpeed, newAmplitude) {
      gl.uniform3f(uColor, newColor[0], newColor[1], newColor[2]);
      gl.uniform1f(uSpeed, newSpeed);
      gl.uniform1f(uAmplitude, newAmplitude);
    }
  };
}

export const Iridescence = {
  mounted() {
    const { color, speed, amplitude } = this.el.dataset;
    this._gl = initWebGL(
      this.el,
      color ? JSON.parse(color) : [0.3, 0.2, 0.5],
      speed ? +speed : 0.4,
      amplitude ? +amplitude : 0.6
    );
  },
  updated() {
    if (this._gl) {
      const { color, speed, amplitude } = this.el.dataset;
      this._gl.updateParams(
        color ? JSON.parse(color) : [0.3, 0.2, 0.5],
        speed ? +speed : 0.4,
        amplitude ? +amplitude : 0.6
      );
    }
  },
  destroyed() {
    if (this._gl) this._gl.destroy();
  }
};
