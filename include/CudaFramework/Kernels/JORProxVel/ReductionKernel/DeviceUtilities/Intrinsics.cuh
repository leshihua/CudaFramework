// ========================================================================================
//  CudaFramework
//  Copyright (C) 2014 by Gabriel Nützi <nuetzig (at) imes (d0t) mavt (d0t) ethz (d0t) ch>
//
//  This Source Code Form is subject to the terms of the GNU GPL 3.0 licence. 
//  If a copy of the GNU GPL 3.0 was not distributed with this
//  file, you can obtain one at http://opensource.org/licenses/GPL-3.0.
// ========================================================================================

/******************************************************************************
 * Copyright (c) 2013, NVIDIA CORPORATION.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the NVIDIA CORPORATION nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 ******************************************************************************/

/******************************************************************************
 *
 * Code and text by Sean Baxter, NVIDIA Research
 * See http://nvlabs.github.io/moderngpu for repository and documentation.
 *
 ******************************************************************************/
#ifndef CudaFramework_Kernels_JORProxVel_ReductionKernel_DeviceUtilities_Intrinsics_cuh
#define CudaFramework_Kernels_JORProxVel_ReductionKernel_DeviceUtilities_Intrinsics_cuh

//#include "../deviceutilities/devicetypes.cuh"
#include <cuda_runtime.h>


namespace ReductionGPU {


__device__ int2 double_as_int2(double x) {
	return *reinterpret_cast<int2*>(&x);
}


__device__ double int2_as_double(int2 x) {
	return *reinterpret_cast<double*>(&x);
}



////////////////////////////////////////////////////////////////////////////////
// PTX for bfe and bfi

#if __CUDA_ARCH__ >= 200

__device__ uint bfe_ptx(uint x, uint bit, uint numBits) {
	uint result;
	asm("bfe.u32 %0, %1, %2, %3;" :
		"=r"(result) : "r"(x), "r"(bit), "r"(numBits));
	return result;
}


__device__ uint bfi_ptx(uint x, uint y, uint bit, uint numBits) {
	uint result;
	asm("bfi.b32 %0, %1, %2, %3, %4;" :
		"=r"(result) : "r"(x), "r"(y), "r"(bit), "r"(numBits));
	return result;
}

__device__ uint prmt_ptx(uint a, uint b, uint index) {
	uint ret;
	asm("prmt.b32 %0, %1, %2, %3;" : "=r"(ret) : "r"(a), "r"(b), "r"(index));
	return ret;
}

#endif // __CUDA_ARCH__ >= 200


// Count leading zeros - start from most significant bit.
__device__ int clz(int x) {
#if __CUDA_ARCH__ >= 200
	return __clz(x);
#else
	for(int i = 31; i >= 0; --i)
		if((1<< i) & x) return 31 - i;
	return 32;
#endif
}

// Find first set - start from least significant bit. LSB is 1. ffs(0) is 0.
MGPU_HOST_DEVICE int ffs(int x) {
#if __CUDA_ARCH__ >= 200
	return __ffs(x);
#else
	for(int i = 0; i < 32; ++i)
		if((1<< i) & x) return i + 1;
	return 0;
#endif
}

MGPU_HOST_DEVICE uint bfe(uint x, uint bit, uint numBits) {
#if __CUDA_ARCH__ >= 200
	return bfe_ptx(x, bit, numBits);
#else
	return ((1<< numBits) - 1) & (x>> bit);
#endif
}

MGPU_HOST_DEVICE uint bfi(uint x, uint y, uint bit, uint numBits) {
	uint result;
#if __CUDA_ARCH__ >= 200
	result = bfi_ptx(x, y, bit, numBits);
#else
	if(bit + numBits > 32) numBits = 32 - bit;
	uint mask = ((1<< numBits) - 1)<< bit;
	result = y & ~mask;
	result |= mask & (x<< bit);
#endif
	return result;
}

MGPU_HOST_DEVICE uint prmt(uint a, uint b, uint index) {
	uint result;
#if __CUDA_ARCH__ >= 200
	result = prmt_ptx(a, b, index);
#else
	result = 0;
	for(int i = 0; i < 4; ++i) {
		uint sel = 0xf & (index>> (4 * i));
		uint x = ((7 & sel) > 3) ? b : a;
		x = 0xff & (x>> (8 * (3 & sel)));
		if(8 & sel) x = (128 & x) ? 0xff : 0;
		result |= x<< (8 * i);
	}
#endif
	return result;
}

// Find log2(x) and optionally round up to the next integer logarithm.
__device__ int FindLog2(int x, bool roundUp = false) {
	int a = 31 - clz(x);
	if(roundUp) a += !MGPU_IS_POW_2(x);
	return a;
}

////////////////////////////////////////////////////////////////////////////////
// vset4

#if __CUDA_ARCH__ >= 300

// Performs four byte-wise comparisons and returns 1 for each byte that
// satisfies the conditional, and zero otherwise.
__device__ uint vset4_lt_add_ptx(uint a, uint b, uint c) {
	uint result;
	asm("vset4.u32.u32.lt.add %0, %1, %2, %3;" :
		"=r"(result) : "r"(a), "r"(b), "r"(c));
	return result;
}
__device__ uint vset4_eq_ptx(uint a, uint b) {
	uint result;
	asm("vset4.u32.u32.eq %0, %1, %2, %3;" :
		"=r"(result) : "r"(a), "r"(b), "r"(0));
	return result;
}
#endif // __CUDA_ARCH__ >= 300

__device__ uint vset4_lt_add(uint a, uint b, uint c) {
	uint result;
#if __CUDA_ARCH__ >= 300
	result = vset4_lt_add_ptx(a, b, c);
#else
	result = c;
	if((0x000000ff & a) < (0x000000ff & b)) result += 0x00000001;
	if((0x0000ff00 & a) < (0x0000ff00 & b)) result += 0x00000100;
	if((0x00ff0000 & a) < (0x00ff0000 & b)) result += 0x00010000;
	if((0xff000000 & a) < (0xff000000 & b)) result += 0x01000000;
#endif
	return result;
}

__device__ uint vset4_eq(uint a, uint b) {
	uint result;
#if __CUDA_ARCH__ >= 300
	result = vset4_eq_ptx(a, b);
#else
	result = 0;
	if((0x000000ff & a) == (0x000000ff & b)) result = 0x00000001;
	if((0x0000ff00 & a) == (0x0000ff00 & b)) result += 0x00000100;
	if((0x00ff0000 & a) == (0x00ff0000 & b)) result += 0x00010000;
	if((0xff000000 & a) == (0xff000000 & b)) result += 0x01000000;
#endif
	return result;
}

////////////////////////////////////////////////////////////////////////////////
//

__device__ uint umulhi(uint x, uint y) {
#if __CUDA_ARCH__ >= 100
	return __umulhi(x, y);
#else
	uint64 product = (uint64)x * y;
	return (uint)(product>> 32);
#endif
}

////////////////////////////////////////////////////////////////////////////////
// ldg() function defined for all devices and all types. Only compiles to __ldg
// intrinsic for __CUDA_ARCH__ >= 320 && __CUDA_ARCH__ < 400 for types supported
// by __ldg in sm_32_intrinsics.h

template<typename T>
struct IsLdgType {
	enum { value = false };
};
#define DEFINE_LDG_TYPE(T) \
	template<> struct IsLdgType<T> { enum { value = true }; };

template<typename T, bool UseLDG = IsLdgType<T>::value>
struct LdgShim {
	__device__ static T Ldg(const T* p) {
		return *p;
	}
};

#if __CUDA_ARCH__ >= 320 && __CUDA_ARCH__ < 400

	// List of __ldg-compatible types from sm_32_intrinsics.h.
	DEFINE_LDG_TYPE(char)
	DEFINE_LDG_TYPE(short)
	DEFINE_LDG_TYPE(int)
	DEFINE_LDG_TYPE(long long)
	DEFINE_LDG_TYPE(char2)
	DEFINE_LDG_TYPE(char4)
	DEFINE_LDG_TYPE(short2)
	DEFINE_LDG_TYPE(short4)
	DEFINE_LDG_TYPE(int2)
	DEFINE_LDG_TYPE(int4)
	DEFINE_LDG_TYPE(longlong2)

	DEFINE_LDG_TYPE(unsigned char)
	DEFINE_LDG_TYPE(unsigned short)
	DEFINE_LDG_TYPE(unsigned int)
	DEFINE_LDG_TYPE(unsigned long long)
	DEFINE_LDG_TYPE(uchar2)
	DEFINE_LDG_TYPE(uchar4)
	DEFINE_LDG_TYPE(ushort2)
	DEFINE_LDG_TYPE(ushort4)
	DEFINE_LDG_TYPE(uint2)
	DEFINE_LDG_TYPE(uint4)
	DEFINE_LDG_TYPE(ulonglong2)

	DEFINE_LDG_TYPE(float)
	DEFINE_LDG_TYPE(double)
	DEFINE_LDG_TYPE(float2)
	DEFINE_LDG_TYPE(float4)
	DEFINE_LDG_TYPE(double2)

	template<typename T> struct LdgShim<T, true> {
		__device__ static T Ldg(const T* p) {
			return __ldg(p);
		}
	};
#endif

template<typename T>
__device__ T ldg(const T* p) {
	return LdgShim<T>::Ldg(p);
}


} // namespace ReductionGPU



# endif // Intrinsics_cuh
