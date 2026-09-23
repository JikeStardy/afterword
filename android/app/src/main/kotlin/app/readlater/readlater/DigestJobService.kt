package app.readlater.readlater

import android.app.job.JobParameters
import android.app.job.JobService

class DigestJobService : JobService() {
    private val runtime: ReadlaterRuntime
        get() = (application as ReadlaterApplication).runtime

    override fun onStartJob(params: JobParameters): Boolean {
        runtime.startDigestJob(this, params)
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        return runtime.stopDigestJob(this, params)
    }
}
