/*
* Copyright (c) 2021, Intel Corporation
*
* Permission is hereby granted, free of charge, to any person obtaining a
* copy of this software and associated documentation files (the "Software"),
* to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense,
* and/or sell copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included
* in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
* OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
* OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
* ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
* OTHER DEALINGS IN THE SOFTWARE.
*/
//!
//! \file     decode_mpeg2_pipeline_adapter_m12.h
//! \brief    Defines the interface to adapt to mpeg2 decode pipeline M12
//!

#ifndef __DECODE_MPEG2_PIPELINE_ADAPTER_M12_H__
#define __DECODE_MPEG2_PIPELINE_ADAPTER_M12_H__

#include "codechal.h"
#include "decode_mpeg2_pipeline_m12.h"
#include "decode_pipeline_adapter.h"

class DecodeMpeg2PipelineAdapterM12 : public DecodePipelineAdapter
{
public:
    DecodeMpeg2PipelineAdapterM12(
        CodechalHwInterface *   hwInterface,
        CodechalDebugInterface *debugInterface);

    virtual ~DecodeMpeg2PipelineAdapterM12()
    {
        if (m_hwInterface)
        {
            MOS_Delete(m_hwInterface);
            Codechal::m_hwInterface = nullptr;
        }
    }

    virtual MOS_STATUS BeginFrame() override;

    virtual MOS_STATUS EndFrame() override;

    virtual MOS_STATUS Allocate(CodechalSetting *codecHalSettings) override;

    virtual MOS_STATUS Execute(void *params) override;

    virtual MOS_STATUS GetStatusReport(void *status, uint16_t numStatus) override;

    virtual uint32_t GetCompletedReport() override;

    virtual bool IsIncompletePicture() override;

    virtual bool IsIncompleteJpegScan() override
    {
        return false; // Just return false since this is for JPEG decode only.
    }

    virtual MOS_SURFACE* GetDummyReference() override;

    virtual CODECHAL_DUMMY_REFERENCE_STATUS GetDummyReferenceStatus() override;

    virtual void SetDummyReferenceStatus(CODECHAL_DUMMY_REFERENCE_STATUS status) override;

    virtual void Destroy() override;

    virtual MOS_GPU_CONTEXT GetDecodeContext() override;

#ifdef _DECODE_PROCESSING_SUPPORTED
    virtual bool IsDownSamplingSupported() override;
#endif

protected:
    std::shared_ptr<decode::Mpeg2PipelineM12> m_decoder;
    CodechalHwInterface                      *m_hwInterface = nullptr;
    MEDIA_CLASS_DEFINE_END(DecodeMpeg2PipelineAdapterM12)
};
#endif // !__DECODE_MPEG2_PIPELINE_ADAPTER_M12_H__