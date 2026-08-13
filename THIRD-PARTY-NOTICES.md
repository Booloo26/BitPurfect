# Third-party notices

BitPurfect statically links the libraries below, so a distributed binary contains their code.
Each licence requires its copyright notice to travel with that binary — this file is how it
does. Ship it alongside the app (it goes in the `.dmg` produced by `make dist`).

Contents:

1. [SimplyCoreAudio — MIT](#1-simplycoreaudio)
2. [mediaremote-adapter — BSD 3-Clause](#2-mediaremote-adapter)
3. [Swift Atomics — Apache License 2.0](#3-swift-atomics)

---

## 1. SimplyCoreAudio

<https://github.com/rnine/SimplyCoreAudio> — used for Core Audio device enumeration and
sample-rate control.

```
Copyright (c) 2014-2021 Ruben Nine

Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

---

## 2. mediaremote-adapter

<https://github.com/ejbills/mediaremote-adapter> — used to receive Apple Music now-playing
events. A fork of <https://github.com/ungive/mediaremote-adapter>, where the technique
originates.

The fork we build against carries **no `LICENSE` file**; the terms are stated in the source
headers instead, for example in `Sources/MediaRemoteAdapter/Resources/run.pl`:

```
Copyright (c) 2025 Jonas van den Berg
This file is licensed under the BSD 3-Clause License.
```

The BSD 3-Clause text those headers refer to:

```
Copyright (c) 2025 Jonas van den Berg and contributors
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
   conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of
   conditions and the following disclaimer in the documentation and/or other materials provided
   with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to
   endorse or promote products derived from this software without specific prior written
   permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

Clause 3 is worth reading before using the authors' names in any promotion of BitPurfect.

---

## 3. Swift Atomics

<https://github.com/apple/swift-atomics> — a transitive dependency of SimplyCoreAudio.

```
Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
Licensed under the Apache License, Version 2.0

Licensed under the Apache License, Version 2.0 (the "License"); you may not use these files
except in compliance with the License. You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the
License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
either express or implied. See the License for the specific language governing permissions and
limitations under the License.
```

The full Apache 2.0 text is at the URL above and in the package's own `LICENSE.txt`.
