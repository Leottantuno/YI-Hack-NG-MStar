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
// A 'ServerMediaSubsession' object that creates new, unicast, "RTPSink"s
// on demand, from a H264 video FIFO.
// Implementation

#include "H264VideoFifoServerMediaSubsession.hh"
#include "H264VideoRTPSink.hh"
#include "ByteStreamFifoSource.hh"
#include "H264VideoStreamFramer.hh"

H264VideoFifoServerMediaSubsession*
H264VideoFifoServerMediaSubsession::createNew(UsageEnvironment& env,
                                              char const* fileName,
                                              Boolean reuseFirstSource) {
  return new H264VideoFifoServerMediaSubsession(env, fileName, reuseFirstSource);
}

H264VideoFifoServerMediaSubsession::H264VideoFifoServerMediaSubsession(UsageEnvironment& env,
                                                                       char const* fileName,
                                                                       Boolean reuseFirstSource)
  : FileServerMediaSubsession(env, fileName, reuseFirstSource),
    fAuxSDPLine(NULL), fDoneFlag(0), fDummyRTPSink(NULL) {
}

H264VideoFifoServerMediaSubsession::~H264VideoFifoServerMediaSubsession() {
  delete[] fAuxSDPLine;
}

static void afterPlayingDummy(void* clientData) {
  H264VideoFifoServerMediaSubsession* subsess = (H264VideoFifoServerMediaSubsession*)clientData;
  subsess->afterPlayingDummy1();
}

void H264VideoFifoServerMediaSubsession::afterPlayingDummy1() {
  envir().taskScheduler().unscheduleDelayedTask(nextTask());
  setDoneFlag();
}

static void checkForAuxSDPLine(void* clientData) {
  H264VideoFifoServerMediaSubsession* subsess = (H264VideoFifoServerMediaSubsession*)clientData;
  subsess->checkForAuxSDPLine1();
}

void H264VideoFifoServerMediaSubsession::checkForAuxSDPLine1() {
  nextTask() = NULL;

  char const* dasl;
  if (fAuxSDPLine != NULL) {
    setDoneFlag();
  } else if (fDummyRTPSink != NULL && (dasl = fDummyRTPSink->auxSDPLine()) != NULL) {
    fAuxSDPLine = strDup(dasl);
    fDummyRTPSink = NULL;
    setDoneFlag();
  } else if (!fDoneFlag) {
    int uSecsToDelay = 100000; // 100 ms
    nextTask() = envir().taskScheduler().scheduleDelayedTask(uSecsToDelay,
                              (TaskFunc*)checkForAuxSDPLine, this);
  }
}

char const* H264VideoFifoServerMediaSubsession::getAuxSDPLine(RTPSink* rtpSink, FramedSource* inputSource) {
  if (fAuxSDPLine != NULL) return fAuxSDPLine;

  if (fDummyRTPSink == NULL) {
    fDummyRTPSink = rtpSink;
    fDummyRTPSink->startPlaying(*inputSource, afterPlayingDummy, this);
    checkForAuxSDPLine(this);
  }

  envir().taskScheduler().doEventLoop(&fDoneFlag);

  return fAuxSDPLine;
}

FramedSource* H264VideoFifoServerMediaSubsession::createNewStreamSource(unsigned /*clientSessionId*/, unsigned& estBitrate) {
  estBitrate = 500; // kbps, estimate

  ByteStreamFifoSource* fifoSource = ByteStreamFifoSource::createNew(envir(), fFileName);
  if (fifoSource == NULL) return NULL;

  return H264VideoStreamFramer::createNew(envir(), fifoSource);
}

RTPSink* H264VideoFifoServerMediaSubsession
::createNewRTPSink(Groupsock* rtpGroupsock,
                   unsigned char rtpPayloadTypeIfDynamic,
                   FramedSource* /*inputSource*/) {
  return H264VideoRTPSink::createNew(envir(), rtpGroupsock, rtpPayloadTypeIfDynamic);
}

