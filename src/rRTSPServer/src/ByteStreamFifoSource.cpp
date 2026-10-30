/**********
This library is free software; you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the
Free Software Foundation; either version 3 of the License, or (at your
option) any later version. (See <http://www.gnu.org/copyleft/lesser.html>.)

This library is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
more details.

You should have received a copy of the GNU Lesser General Public License
along with this library; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
**********/
// "liveMedia"
// A fifo file source that is a plain byte stream (rather than frames)
// Implementation

#include "ByteStreamFifoSource.hh"
#include "InputFile.hh"
#include "GroupsockHelper.hh"
#include "rRTSPServer.h"

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

extern int debug;

////////// ByteStreamFifoSource //////////

ByteStreamFifoSource*
ByteStreamFifoSource::createNew(UsageEnvironment& env, char const* fileName,
                                unsigned playTimePerFrame) {
    FILE* fid = OpenInputFile(env, fileName);
    if (fid == NULL) return NULL;

    makeSocketNonBlocking(fileno(fid));

    return new ByteStreamFifoSource(env, fid, playTimePerFrame);
}

ByteStreamFifoSource*
ByteStreamFifoSource::createNew(UsageEnvironment& env, FILE* fid,
                                unsigned playTimePerFrame) {
    if (fid == NULL) return NULL;

    makeSocketNonBlocking(fileno(fid));

    return new ByteStreamFifoSource(env, fid, playTimePerFrame);
}

ByteStreamFifoSource::ByteStreamFifoSource(UsageEnvironment& env, FILE* fid,
                                           unsigned playTimePerFrame)
    : FramedFileSource(env, fid), fPlayTimePerFrame(playTimePerFrame),
      fHaveStartedReading(False) {
}

ByteStreamFifoSource::~ByteStreamFifoSource() {
    if (fFid == NULL) return;

    envir().taskScheduler().unscheduleDelayedTask(nextTask());
    envir().taskScheduler().turnOffBackgroundReadHandling(fileno(fFid));
    CloseInputFile(fFid);
}

void ByteStreamFifoSource::cleanFifo() {
    if (fFid == NULL) return;

    int flags = fcntl(fileno(fFid), F_GETFL, 0);
    if (flags >= 0) {
        fcntl(fileno(fFid), F_SETFL, flags | O_NONBLOCK);
    }

    if (debug & 4) fprintf(stderr, "%lld: ByteStreamFifoSource - cleaning fifo\n", current_timestamp());

    unsigned char null[512];
    while (read(fileno(fFid), null, sizeof(null)) > 0) {}

    if (debug & 4) fprintf(stderr, "%lld: ByteStreamFifoSource - fifo cleaned\n", current_timestamp());
}

void ByteStreamFifoSource::doGetNextFrame() {
    if (feof(fFid)) {
        clearerr(fFid);
    }

    fFrameSize = 0;
    if (!fHaveStartedReading) {
        cleanFifo();
        fHaveStartedReading = True;
    }
    doReadFromFile();
}

void ByteStreamFifoSource::doStopGettingFrames() {
    if (debug & 4) fprintf(stderr, "%lld: ByteStreamFifoSource - doStopGettingFrames\n", current_timestamp());
    envir().taskScheduler().unscheduleDelayedTask(nextTask());
    nextTask() = NULL;
    envir().taskScheduler().turnOffBackgroundReadHandling(fileno(fFid));
    fHaveStartedReading = False;
}

void ByteStreamFifoSource::fileReadableHandler(ByteStreamFifoSource* source, int /*mask*/) {
    source->doReadFromFile();
}

void ByteStreamFifoSource::readTimeoutHandler(void* clientData) {
    ByteStreamFifoSource* source = (ByteStreamFifoSource*)clientData;
    source->doReadFromFile();
}

void ByteStreamFifoSource::doReadFromFile() {
    if (feof(fFid)) {
        clearerr(fFid);
    }

    ssize_t numBytesRead = read(fileno(fFid), fTo, fMaxSize);
    if (numBytesRead > 0) {
        fFrameSize = (unsigned)numBytesRead;
        gettimeofday(&fPresentationTime, NULL);

        envir().taskScheduler().unscheduleDelayedTask(nextTask());
        envir().taskScheduler().turnOffBackgroundReadHandling(fileno(fFid));

        nextTask() = envir().taskScheduler().scheduleDelayedTask(0,
                             (TaskFunc*)FramedSource::afterGetting, this);
        return;
    }

    // Live FIFO: writer paused or transient empty buffer.
    // Never call handleClosure(). Wait for readability via taskScheduler.
    envir().taskScheduler().turnOnBackgroundReadHandling(fileno(fFid),
        (TaskScheduler::BackgroundHandlerProc*)&fileReadableHandler, this);

    nextTask() = envir().taskScheduler().scheduleDelayedTask(10000,
        (TaskFunc*)ByteStreamFifoSource::readTimeoutHandler, this);
}

