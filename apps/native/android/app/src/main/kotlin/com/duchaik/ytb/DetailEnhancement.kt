package com.duchaik.ytb

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

/** Bounded spatial detail enhancement. No generated detail, frame interpolation or color shift. */
class DetailEnhancement(private val amount: Float) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram = Program(useHdr, amount)
    private class Program(hdr: Boolean, amount: Float) : BaseGlShaderProgram(hdr, 1) {
        private val program = GlProgram(
            """attribute vec4 aPosition;
               varying vec2 vTex;
               void main() { gl_Position = aPosition; vTex = aPosition.xy * 0.5 + 0.5; }""",
            """precision highp float;
               uniform sampler2D uTexture;
               uniform vec2 uStep;
               uniform float uAmount;
               varying vec2 vTex;
               void main() {
                 vec4 c = texture2D(uTexture, vTex);
                 vec3 a = texture2D(uTexture, vTex + vec2(uStep.x, 0.0)).rgb;
                 vec3 b = texture2D(uTexture, vTex - vec2(uStep.x, 0.0)).rgb;
                 vec3 d = texture2D(uTexture, vTex + vec2(0.0, uStep.y)).rgb;
                 vec3 e = texture2D(uTexture, vTex - vec2(0.0, uStep.y)).rgb;
                 vec3 detail = c.rgb - (a+b+d+e)*0.25;
                 float strength = smoothstep(0.003, 0.035, length(detail));
                 vec3 lo = min(c.rgb, min(min(a,b),min(d,e)));
                 vec3 hi = max(c.rgb, max(max(a,b),max(d,e)));
                 gl_FragColor = vec4(clamp(c.rgb + clamp(detail, vec3(-0.035), vec3(0.035))*uAmount*strength, lo, hi), c.a);
               }"""
        ).apply {
            setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
            setFloatUniform("uAmount", amount)
        }
        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            program.setFloatsUniform("uStep", floatArrayOf(1f/inputWidth, 1f/inputHeight))
            return Size(inputWidth, inputHeight)
        }
        override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
            try {
                program.use(); program.setSamplerTexIdUniform("uTexture", inputTexId, 0)
                program.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GlUtil.checkGlError()
            } catch (e: GlUtil.GlException) { throw VideoFrameProcessingException(e, presentationTimeUs) }
        }
        override fun release() { super.release(); program.delete() }
    }
}
