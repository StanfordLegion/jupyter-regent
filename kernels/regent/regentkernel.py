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

import os
import time
import stat
from subprocess import Popen, PIPE
from ipykernel.kernelbase import Kernel
from datetime import datetime

class RegentKernel(Kernel):
    implementation = 'Regent'
    implementation_version = '1.0'
    language = 'regent'
    language_version = '0.1'
    language_info = { 'mimetype': 'text/x-regent', 'name': 'regent',
            'pygments_lexer': 'lua', 'file_extension': 'rg' }
    banner = "IPython kernel for Regent"

    def do_execute(self, code, silent, store_history=True,
            user_expressions=None, allow_stdin=False):
        if not silent:
            dir = datetime.now().strftime("kernellaunch-%Y-%m-%d-%M-%S.%f")
            tmp_dir = os.path.join("/var/jupyterhub/launches", dir)
            os.mkdir(tmp_dir)
            os.chmod(tmp_dir, stat.S_IRWXO + stat.S_IRWXG + stat.S_IRWXU)

            regent_file = "test.rg"
            torque_file = "run.sh"

            regent_file_path = os.path.join(tmp_dir, regent_file)
            torque_file_path = os.path.join(tmp_dir, torque_file)

            with open(regent_file_path, "w") as file:
                file.write(code)

            num_nodes = 1
            prof_file = "legion_prof_%.log"
            prof_file_path = os.path.join(tmp_dir, prof_file)
            regent_interpreter_path = "regent"

            with open(torque_file_path, "w") as file:
                file.write("#!/bin/bash -l\n")
                file.write("#PBS -l nodes=%d\n" % num_nodes)
                file.write("%s %s -hl:prof %d -level legion_prof=2 -logfile %s\n" % \
                        (regent_interpreter_path,
                            regent_file_path,
                            num_nodes,
                            prof_file_path))

            stdout_file_path = os.path.join(tmp_dir, "stdout")
            stderr_file_path = os.path.join(tmp_dir, "stderr")
            # submit the job to torque
            job_process = Popen(["qsub", torque_file_path,
                "-o", stdout_file_path, "-e", stderr_file_path],
                stdout=PIPE, stderr=PIPE)
            job_id = job_process.stdout.read()

            # wait until the job finishes
            delay = 0.0001
            check_result = ""
            while check_result == "":
                check_process = Popen(["qstat", "-f", job_id,
                    "|", "grep", "\"job_state = C\""], stdout=PIPE, stderr=PIPE)
                check_result = check_process.stdout.read().strip()
                if not os.path.isfile(stdout_file_path) or \
                        not os.path.isfile(stderr_file_path):
                    check_result = ""
                time.sleep(delay)
                delay = delay * 2

            with open(stdout_file_path, "r") as file:
                output = file.read()

            stream_content = {'name': 'stdout', 'text': output}
            self.send_response(self.iopub_socket, 'stream', stream_content)

        return {'status': 'ok',
                # The base class increments the execution count
                'execution_count': self.execution_count,
                'payload': [],
                'user_expressions': {},
               }

if __name__ == '__main__':
    from ipykernel.kernelapp import IPKernelApp
    IPKernelApp.launch_instance(kernel_class=RegentKernel)
