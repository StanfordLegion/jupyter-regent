#!/usr/bin/env python

# Copyright 2015 Stanford University
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from __future__ import print_function
import os, subprocess, sys

def launcher(argv):
    nodes = 1
    if 'PBS_NODEFILE' in os.environ:
        with open(os.environ['PBS_NODEFILE'], 'rb') as f:
            nodes = len(set(f.read().split()))
    else:
        print('WARNING: PBS_NODEFILE unset. Running outside of Torque?')
    env = dict(os.environ.items() + [
        ('LAUNCHER', 'amudprun -np {} -spawn C'.format(nodes)),
        ('GASNET_CSPAWN_CMD', 'mpirun -npernode 1 -bind-to-none -x INCLUDE_PATH -x LD_LIBRARY_PATH -x TERRA_PATH %C'),
    ])
    return subprocess.Popen(argv, env = env)

if __name__ == '__main__':
    sys.exit(launcher(sys.argv[1:]).wait())
