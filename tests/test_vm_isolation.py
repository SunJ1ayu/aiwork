"""Guest observations, using synthetic mount tables and disposable trees only."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

import importlib.machinery
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_checker():
    loader = importlib.machinery.SourceFileLoader('vm_isolation', str(ROOT / 'bin/check-vm-isolation'))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def mount(fs='ext4', target='/', source='/dev/vda1', root='/'):
    return f'25 1 254:1 {root} {target} rw,relatime - {fs} {source} rw\n'


class VmIsolationTests(unittest.TestCase):
    def setUp(self):
        self.check = load_checker()

    def test_local_disk_and_kernel_mounts_pass(self):
        table = (mount() + mount('proc', '/proc', 'proc') + mount('tmpfs', '/run', 'tmpfs')
                 + mount('bpf', '/sys/fs/bpf', 'bpf') + mount('nsfs', '/run/netns/test', 'nsfs'))
        self.assertEqual(self.check.check_mounts(table), [])

    def test_every_host_share_transport_fails_even_read_only_or_renamed(self):
        for fs in ('virtiofs', '9p', 'fuse.sshfs', 'fuse', 'nfs', 'nfs4', 'cifs', 'smb3', 'vboxsf', 'vmhgfs', 'unknown-fs'):
            with self.subTest(fs=fs):
                failures = self.check.check_mounts(mount() + mount(fs, '/arbitrary', 'share').replace('rw', 'ro'))
                self.assertTrue(failures)
                self.assertIn('MOUNT', ' '.join(failures))

    def test_mac_paths_in_mount_target_root_or_source_fail_including_escapes(self):
        for field in ('target', 'root', 'source'):
            for path in ('/Users/example', '/Volumes/disk', '/System/Volumes/Data', r'/Users/example\040name'):
                with self.subTest(field=field, path=path):
                    self.assertIn('MAC_PATH', ' '.join(self.check.check_mounts(mount(**{field: path}))))

    def test_malformed_or_empty_observation_cannot_pass(self):
        for table in ('', '\n', 'unparseable', '25 1 0:1 / / rw - ext4', mount().replace('25', 'x', 1)):
            with self.subTest(table=table):
                self.assertIn('OBSERVATION', ' '.join(self.check.check_mounts(table)))

    def test_visible_mac_roots_and_openclaw_state_fail_without_reading_contents(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            homes = [root / 'root', root / 'home/aiwork']
            for relative, rule in (
                ('Users', 'MAC_PATH'), ('Volumes', 'MAC_PATH'),
                ('System/Volumes/Data', 'MAC_PATH'),
                ('root/.openclaw', 'OPENCLAW'),
                ('home/aiwork/.config/openclaw', 'OPENCLAW'),
                ('home/aiwork/Library/Application Support/OpenClaw', 'OPENCLAW'),
                ('Applications/OpenClaw.app', 'OPENCLAW'),
                ('run/host-services/ssh-auth.sock', 'SSH_AGENT'),
                ('home/aiwork/Library/Application Support/aiwork', 'MAC_SETTINGS'),
            ):
                with self.subTest(relative=relative):
                    path = root / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.mkdir()
                    self.assertIn(rule, ' '.join(self.check.check_paths(root, homes)))
                    path.rmdir()

    def test_guest_aiwork_settings_are_allowed_but_mac_settings_link_is_not(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            home = root / 'home/aiwork'
            config = home / '.config/aiwork'
            config.mkdir(parents=True)
            self.assertEqual(self.check.check_paths(root, [home]), [])
            config.rmdir()
            config.symlink_to('/Users/example/.config/aiwork')
            self.assertIn('MAC_SETTINGS', ' '.join(self.check.check_paths(root, [home])))

    def test_forwarded_agent_or_openclaw_command_fails(self):
        self.assertIn('SSH_AGENT', ' '.join(self.check.check_environment({'SSH_AUTH_SOCK': '/run/agent'}, None)))
        self.assertIn('OPENCLAW', ' '.join(self.check.check_environment({}, '/bin/openclaw')))
        self.assertEqual(self.check.check_environment({}, None), [])

    def test_failed_reads_and_wrong_namespace_or_identity_fail_closed(self):
        with patch.object(self.check.os, 'geteuid', return_value=0):
            for error in (PermissionError, FileNotFoundError):
                with patch.object(self.check.os, 'readlink', return_value='mnt:[1]'), \
                     patch.object(self.check.Path, 'read_text', side_effect=error):
                    self.assertNotEqual(self.check.main([]), 0)
            with patch.object(self.check.os, 'readlink', side_effect=['mnt:[2]', 'mnt:[1]']):
                self.assertNotEqual(self.check.main([]), 0)
        with patch.object(self.check.os, 'geteuid', return_value=1000):
            self.assertNotEqual(self.check.main([]), 0)

    def test_entrypoint_has_no_fixture_or_skip_switch(self):
        result = subprocess.run([sys.executable, str(ROOT / 'bin/check-vm-isolation'), '--mountinfo', '/dev/null'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('参数', result.stderr)

    def test_template_has_no_host_sharing_or_implicit_base(self):
        template = json.loads((ROOT / 'templates/linux-vm.yaml').read_text())
        self.assertEqual(template['arch'], 'aarch64')
        self.assertEqual(template['vmType'], 'vz')
        self.assertNotIn('base', template)
        for key in ('mounts', 'additionalDisks', 'copyToHost'):
            self.assertEqual(template[key], [])
        for key in ('forwardAgent', 'forwardX11', 'loadDotSSHPubKeys'):
            self.assertIs(template['ssh'][key], False)
        self.assertIs(template['propagateProxyEnv'], False)
        self.assertEqual(template['portForwards'], [{'guestPortRange': [1, 65535], 'ignore': True}])
        self.assertFalse(template['containerd']['system'])
        self.assertFalse(template['containerd']['user'])
        self.assertTrue(template['images'])
        for image in template['images']:
            self.assertIn('release-', image['location'])
            self.assertRegex(image['digest'], r'^sha256:[a-f0-9]{64}$')

    def test_install_node_major_tracks_linux_ci(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        guide = (ROOT / 'docs/linux-vm.md').read_text()
        ci_version = re.search(r'node-version:\s*"(\d+)"', ci)[1]
        install_version = re.search(r'^AIWORK_NODE_VERSION=(\d+)\.', guide, re.M)[1]
        self.assertEqual(install_version, ci_version)

    def test_release_references_track_their_definitions(self):
        template = json.loads((ROOT / 'templates/linux-vm.yaml').read_text())
        guide = (ROOT / 'docs/linux-vm.md').read_text()
        lima_refs = re.findall(r'(?:lima-|lima/releases/tag/v)(\d+\.\d+\.\d+)', guide)
        self.assertTrue(lima_refs)
        self.assertEqual(set(lima_refs), {template['minimumLimaVersion']})
        autoloop_tags = re.findall(r'^AUTOLOOP_TAG=(v\d+\.\d+\.\d+)$', guide, re.M)
        self.assertEqual(len(autoloop_tags), 1)
        autoloop_tag = autoloop_tags[0]
        autoloop_refs = re.findall(r'agent-autoloop/(?:releases/tag|blob)/(v\d+\.\d+\.\d+)', guide)
        self.assertTrue(autoloop_refs)
        self.assertEqual(set(autoloop_refs), {autoloop_tag})


if __name__ == '__main__':
    unittest.main()
