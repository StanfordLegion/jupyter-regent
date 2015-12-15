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

import base64
import collections
import glob
import ipykernel.kernelapp
import ipykernel.kernelbase
import os
import shutil
import stat
import subprocess
import tempfile
import time

def parse_attribute(attribute, is_first):
    attribute = ''.join(attribute)
    if is_first:
        key, value = attribute.split(': ', 1)
        return (key.lower().replace(' ', '_'), value)
    key, value = attribute.split(' = ', 1)
    return (key.lower().replace(' ', '_'), value)

def parse_status(logs):
    entries = [entry for entry in logs.split('\n\n') if len(entry.strip()) > 0]
    jobs = []
    for entry in entries:
        lines = entry.split('\n')
        job = []
        attribute = None
        is_first = True
        for line in lines:
            if line.startswith('\t'):
                attribute.append(line.strip())
            else:
                if attribute is not None:
                    job.append(parse_attribute(attribute, is_first))
                    is_first = False
                attribute = [line.strip()]
        job.append(parse_attribute(attribute, is_first))
        jobs.append(dict(job))
    return jobs

class RegentKernel(ipykernel.kernelbase.Kernel):
    implementation = 'Regent'
    implementation_version = '1.0'
    language = 'regent'
    language_version = '0.1'
    language_info = {
        'mimetype': 'text/x-regent',
        'name': 'regent',
        'pygments_lexer': 'lua',
        'file_extension': 'rg',
    }
    banner = 'Jupyter kernel for Regent'

    def do_execute(self, code, silent, store_history=True,
                   user_expressions=None, allow_stdin=False):
        # Execution is side-effect free, so silent doesn't do anything.
        if silent:
            return {
                'status': 'ok',
                # The base class increments the execution count
                'execution_count': self.execution_count,
                'payload': [],
                'user_expressions': {},
            }

        use_torque = 'torque' in os.environ and os.environ['torque'] == 'true'

        root_dir = os.path.dirname(os.path.realpath(__file__))
        tmp_dir = tempfile.mkdtemp(
            dir=('/var/jupyterhub/launches' if use_torque else None))

        regent_file_path = os.path.join(tmp_dir, 'test.rg')
        with open(regent_file_path, 'w') as file:
            file.write(code)

        regent_interpreter_path = 'regent'

        if not use_torque:
            proc = subprocess.Popen(
                [regent_interpreter_path, regent_fiel_path, '-ll:cpu', '1', '-ll:csize', '100'],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stdout, stderr = proc.communicate()

            self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': stdout.decode('utf-8')})
            self.send_response(self.iopub_socket, 'stream', {'name': 'stderr', 'text': stderr.decode('utf-8')})

            if proc.returncode != 0:
                self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': 'Exited with return code %s.\n' % proc.returncode})
                return {
                    'status': 'error',
                    'execution_count': self.execution_count,
                    'ename': '',
                    'evalue': str(proc.returncode),
                    'traceback': [],
                }
        else:
            launcher_dir = os.path.join(os.path.dirname(os.path.dirname(root_dir)), 'launcher')

            # FIXME: Find a way to un-hard-code these values.
            num_nodes = 4
            prof_file_path = os.path.join(tmp_dir, 'legion_prof_%.log')
            torque_file_path = os.path.join(tmp_dir, 'run.sh')
            with open(torque_file_path, 'w') as f:
                f.write('#!/bin/bash -l\n')
                # f.write('#PBS -l nodes=%d\n' % num_nodes)
                f.write('%s %s %s -hl:prof %d -level legion_prof=2 -logfile %s -ll:cpu 16 -ll:gpu 4 -ll:csize 16384 -ll:rsize 2048 -ll:gsize 0 -ll:fsize 2048 -ll:zsize 2048\n' % (
                    launcher_file_path,
                    regent_interpreter_path,
                    regent_file_path,
                    num_nodes,
                    prof_file_path))

            launcher_file_path = os.path.join(tmp_dir, 'launcher.py')
            shutil.copy2(os.path.join(launcher_dir, 'launcher.py'), launcher_file_path)

            stdout_file_path = os.path.join(tmp_dir, 'stdout')
            stderr_file_path = os.path.join(tmp_dir, 'stderr')

            # Submit the job to Torque.
            job_process = subprocess.Popen(
                ['qsub', torque_file_path,
                 '-d', os.path.join(os.path.expanduser('~'), 'notebooks'),
                 '-o', stdout_file_path,
                 '-e', stderr_file_path],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            job_out, job_err = job_process.communicate()
            # If submission failed, abort.
            if job_process.returncode != 0:
                # Make a best-effort attempt to kill existing jobs.
                subprocess.Popen(['qdel', 'all'], stdout=subprocess.PIPE, stderr=subprocess.PIPE).wait()

                self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': job_out.decode('utf-8')})
                self.send_response(self.iopub_socket, 'stream', {'name': 'stderr', 'text': job_err.decode('utf-8')})
                return {
                    'status': 'error',
                    'execution_count': self.execution_count,
                    'ename': '',
                    'evalue': str(job_process.returncode),
                    'traceback': [],
                }
            job_id = job_out.decode('utf-8').strip()
            assert(len(job_id) > 0)
            self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': 'Submitted job %s' % job_id})

            # Wait until the job finishes.
            delay = 0.25
            running = True
            exitcode = -1
            error = False
            while running:
                status = parse_status(subprocess.check_output(['qstat', '-f', job_id]).decode('utf-8'))[0]
                self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': '.'})
                if status['job_state'] == 'C':
                    running = False
                    if 'exit_status' in status: exitcode = int(status['exit_status'])
                    error = exitcode != 0
                    break
                time.sleep(delay)
                delay = min(delay * 2, 10)
            self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': ' finished.\n'})

            with open(stdout_file_path, 'r') as f:
                self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': f.read()})
            with open(stderr_file_path, 'r') as f:
                self.send_response(self.iopub_socket, 'stream', {'name': 'stderr', 'text': f.read()})

            if error:
                self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': 'Exited with return code %s.\n' % exitcode})
                return {
                    'status': 'error',
                    'execution_count': self.execution_count,
                    'ename': '',
                    'evalue': str(exitcode),
                    'traceback': [],
                }

            prof_file_paths = ' '.join(glob.glob(os.path.join(tmp_dir, 'legion_prof_*.log')))
            html_file_path = os.path.join('/var/www/files', dir)
            os.mkdir(html_file_path)
            html_file_prefix = os.path.join(html_file_path, 'legion_prof')
            legion_prof_path = os.path.join('/usr/local/legion/tools/legion_prof.py')
            subprocess.check_output(['python', legion_prof_path, '-o', html_file_prefix, '-T', prof_file_paths])
            # self.send_response(self.iopub_socket, 'stream', {'name': 'stdout', 'text': prof_result})
            url = os.path.join('/files', dir, 'legion_prof.html')
            html = '''
                <p>Legion Prof timeline (<a href="%s" target="_blank">open in a new window</a>)</p>
                <iframe src="%s" width="800" height="600"></iframe>''' % (url, url)
            display_content = {'source': 'LegionProf', 'data': { 'text/html': html } }
            self.send_response(self.iopub_socket, 'display_data', display_content)

        return {
            'status': 'ok',
            # The base class increments the execution count
            'execution_count': self.execution_count,
            'payload': [],
            'user_expressions': {},
        }

if __name__ == '__main__':
    ipykernel.kernelapp.IPKernelApp.launch_instance(kernel_class=RegentKernel)
