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
// on demand, from a H265 video FIFO.
// Implementation

#include "H265VideoFifoServerMediaSubsession.hh"
#include "H265VideoRTPSink.hh"
#include "ByteStreamFifoSource.hh"
#include "H265VideoStreamFramer.hh"

H265VideoFifoServerMediaSubsession*
H265VideoFifoServerMediaSubsession::createNew(UsageEnvironment& env,
                                              char const* fileName,
                                              Boolean reuseFirstSource) {
  return new H265VideoFifoServerMediaSubsession(env, fileName, reuseFirstSource);
}

H265VideoFifoServerMediaSubsession::H265VideoFifoServerMediaSubsession(UsageEnvironment& env,
                                                                       char const* fileName,
                                                                       Boolean reuseFirstSource)
  : FileServerMediaSubsession(env, fileName, reuseFirstSource),
    fAuxSDPLine(NULL), fDoneFlag(0), fDummyRTPSink(NULL) {
}

H265VideoFifoServerMediaSubsession::~H265VideoFifoServerMediaSubsession() {
  delete[] fAuxSDPLine;
}

static void afterPlayingDummy(void* clientData) {
  H265VideoFifoServerMediaSubsession* subsess = (H265VideoFifoServerMediaSubsession*)clientData;
  subsess->afterPlayingDummy1();
}

void H265VideoFifoServerMediaSubsession::afterPlayingDummy1() {
  envir().taskScheduler().unscheduleDelayedTask(nextTask());
  setDoneFlag();
}

static void checkForAuxSDPLine(void* clientData) {
  H265VideoFifoServerMediaSubsession* subsess = (H265VideoFifoServerMediaSubsession*)clientData;
  subsess->checkForAuxSDPLine1();
}

void H265VideoFifoServerMediaSubsession::checkForAuxSDPLine1() {
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

char const* H265VideoFifoServerMediaSubsession::getAuxSDPLine(RTPSink* rtpSink, FramedSource* inputSource) {
  if (fAuxSDPLine != NULL) return fAuxSDPLine;

  if (fDummyRTPSink == NULL) {
    fDummyRTPSink = rtpSink;
    fDummyRTPSink->startPlaying(*inputSource, afterPlayingDummy, this);
    checkForAuxSDPLine(this);
  }

  envir().taskScheduler().doEventLoop(&fDoneFlag);

  return fAuxSDPLine;
}

FramedSource* H265VideoFifoServerMediaSubsession::createNewStreamSource(unsigned /*clientSessionId*/, unsigned& estBitrate) {
  estBitrate = 500; // kbps, estimate

  ByteStreamFifoSource* fifoSource = ByteStreamFifoSource::createNew(envir(), fFileName);
  if (fifoSource == NULL) return NULL;

  return H265VideoStreamFramer::createNew(envir(), fifoSource);
}

RTPSink* H265VideoFifoServerMediaSubsession
::createNewRTPSink(Groupsock* rtpGroupsock,
                   unsigned char rtpPayloadTypeIfDynamic,
                   FramedSource* /*inputSource*/) {
  return H265VideoRTPSink::createNew(envir(), rtpGroupsock, rtpPayloadTypeIfDynamic);
}

