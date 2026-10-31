package com.duchaik.ytb

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.datasource.TransferListener
import java.io.EOFException

/** Bounded HTTPS Range requests avoid requesting a whole long YouTube media file. */
class ChunkedHttpDataSource(headers: Map<String, String>) : DataSource {
    private val upstream = OkHttpDataSource.Factory(MediaHttp.mediaClient)
        .setDefaultRequestProperties(headers).createDataSource()
    private var spec: DataSpec? = null
    private var position = 0L
    private var remaining = C.LENGTH_UNSET.toLong()
    private var chunkRemaining = 0L
    private var opened = false
    override fun addTransferListener(listener: TransferListener) = upstream.addTransferListener(listener)
    override fun getUri(): Uri? = spec?.uri
    override fun getResponseHeaders(): Map<String, List<String>> = upstream.responseHeaders
    override fun open(dataSpec: DataSpec): Long {
        spec=dataSpec;position=dataSpec.position;remaining=dataSpec.length
        openChunk()
        return remaining
    }
    private fun openChunk() {
        if(opened) {upstream.close();opened=false}
        val size=if(remaining==C.LENGTH_UNSET.toLong())CHUNK else minOf(CHUNK,remaining)
        if(size<=0) {chunkRemaining=0;return}
        val available=upstream.open(spec!!.buildUpon().setPosition(position).setLength(size).build())
        opened=true
        val range=upstream.responseHeaders.entries.firstOrNull{it.key.equals("content-range",true)}?.value?.firstOrNull()
        val match=range?.let{Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(it)}
        if(match!=null) {
            val start=match.groupValues[1].toLong()
            val end=match.groupValues[2].toLong()
            val total=match.groupValues[3].toLong()
            if(start!=position) throw EOFException("Unexpected media range")
            if(remaining==C.LENGTH_UNSET.toLong()) remaining=total-position
            else remaining=minOf(remaining,total-position)
            chunkRemaining=minOf(end-start+1,size)
        }else chunkRemaining=if(available>=0)minOf(available,size) else size
    }
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if(length==0)return 0
        if(remaining==0L)return C.RESULT_END_OF_INPUT
        if(chunkRemaining==0L)openChunk()
        val count=upstream.read(buffer,offset,minOf(length.toLong(),chunkRemaining).toInt())
        if(count==C.RESULT_END_OF_INPUT) {
            if(remaining>0)throw EOFException("Media range ended before its declared length")
            return count
        }
        position+=count;chunkRemaining-=count
        if(remaining!=C.LENGTH_UNSET.toLong())remaining-=count
        return count
    }
    override fun close() {if(opened)upstream.close();opened=false;spec=null}
    companion object {private const val CHUNK=512L*1024}
}
