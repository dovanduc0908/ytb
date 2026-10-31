package com.duchaik.ytb

import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit

/** Shared transport for Facebook media; no undocumented YouTube API client. */
object MediaHttp {
    val mediaClient = OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS).callTimeout(0, TimeUnit.MILLISECONDS).build()
}
