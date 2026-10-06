"""Offline privacy checks through the CLI and real Git repositories."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _no_egress  # noqa: E402,F401

from pathlib import Path
import re
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / 'repo'
        self.repo.mkdir()
        self.config = Path(self.temp.name) / 'settings'
        self.config.mkdir()
        self.env = dict(os.environ, AIWORK_CONFIG_DIR=str(self.config))
        self.git('init', '-q')
        self.git('config', 'user.name', 'fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')

    def git(self, *args, env=None):
        return subprocess.check_output(['git', *args], cwd=self.repo, env=env).decode().strip()

    def check(self, *args, cwd=None):
        return subprocess.run([str(ROOT / 'bin/privacy-check'), *args],
                              cwd=cwd or self.repo, env=self.env, capture_output=True, text=True)

    def terms(self, text=''):
        (self.config / 'private-terms').write_text(text)

    def commit(self, message='fixture', env=None):
        self.git('add', '-A')
        return self.git('commit', '-qm', message, env=env)

    def test_missing_terms_fails_closed_and_reports_location(self):
        result = self.check('--all')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(self.config / 'private-terms'), result.stderr)

    def test_range_checks_additions_paths_and_every_metadata_field_without_echo(self):
        self.terms('PersonalMarker\n')
        (self.repo / 'old.txt').write_text('PersonalMarker old content\n')
        self.commit()
        base = self.git('rev-parse', 'HEAD')
        (self.repo / 'old.txt').write_text('clean\n')
        name = 'PERSONALMARKER-file.txt'
        (self.repo / name).write_text('clean\nsecret personalmarker\n')
        env = dict(self.env, GIT_AUTHOR_NAME='personalmarker',
                   GIT_AUTHOR_EMAIL='PERSONALMARKER@example.invalid',
                   GIT_COMMITTER_NAME='PersonalMarker',
                   GIT_COMMITTER_EMAIL='personalmarker@example.invalid')
        self.commit('title\n\nPERSONALMARKER body', env)
        result = self.check(base + '..HEAD')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn('personalmarker', (result.stdout + result.stderr).casefold())
        self.assertNotIn('old.txt', result.stdout)
        self.assertIn('[隐藏文件路径]:0 私人词第 1 条', result.stdout)
        self.assertIn('[隐藏文件路径]:2 私人词第 1 条', result.stdout)
        for field in ('author-name', 'author-email', 'committer-name', 'committer-email', 'message'):
            self.assertIn('/' + field + ':', result.stdout)

    def test_all_and_selected_untracked_files_check_shapes_and_term_numbering(self):
        self.terms('\nunused\nPrIvAtE-MaRkEr\n')
        secret = 'tp' + '-' + 'a' * 48
        (self.repo / 'new.txt').write_text('safe\n' + secret + '\nPRIVATE-MARKER\n')
        for args in (('--all',), ('--files', 'new.txt')):
            with self.subTest(args=args):
                result = self.check(*args)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn('new.txt:2 形状 tp-', result.stdout)
                self.assertIn('new.txt:3 私人词第 3 条', result.stdout)
                self.assertNotIn(secret, result.stdout + result.stderr)
                self.assertNotIn('PRIVATE-MARKER', result.stdout + result.stderr)

    def test_history_includes_root_and_secrets_removed_before_tip(self):
        self.terms()
        secret = 'sk' + '-' + 'a' * 20
        (self.repo / 'removed.txt').write_text(secret + '\n')
        self.commit()
        (self.repo / 'removed.txt').unlink()
        (self.repo / 'safe.txt').write_text('safe\n')
        self.commit()
        self.assertEqual(self.check('--all').returncode, 0)
        result = self.check('HEAD')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('removed.txt:1 形状 sk-', result.stdout)
        self.assertNotIn(secret, result.stdout + result.stderr)

    def test_newline_filename_and_symlink_are_safe_and_do_not_read_external_targets(self):
        self.terms('private-marker\n')
        outside = Path(self.temp.name) / 'outside'
        outside.write_text('private-marker\n')
        (self.repo / 'link').symlink_to(outside)
        (self.repo / 'line\nbreak.txt').write_text('private-marker\n')
        result = self.check('--all')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, 'line\\nbreak.txt:1 私人词第 1 条\n')

    def test_invalid_revision_and_missing_selected_file_fail_closed_without_echo(self):
        self.terms('private-marker\n')
        for args in (('private-marker',), ('--files', 'private-marker')):
            result = self.check(*args)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn('private-marker', result.stdout + result.stderr)

    def test_binary_additions_rename_and_merge_do_not_escape_the_range_check(self):
        self.terms('private-marker\n')
        (self.repo / 'old.txt').write_text('safe\n')
        self.commit()
        base = self.git('rev-parse', 'HEAD')
        self.git('checkout', '-qb', 'topic')
        (self.repo / 'binary.dat').write_bytes(b'\0PRIVATE-MARKER\n')
        self.git('mv', 'old.txt', 'private-marker.txt')
        self.commit()
        self.git('checkout', '-q', '-')
        (self.repo / 'main.txt').write_text('safe\n')
        self.commit()
        self.git('merge', '--no-ff', '-qm', 'fixture merge', 'topic')
        result = self.check(base + '..HEAD')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('binary.dat:1 私人词第 1 条', result.stdout)
        self.assertIn('[隐藏文件路径]:0 私人词第 1 条', result.stdout)
        self.assertNotIn('private-marker', (result.stdout + result.stderr).casefold())

    def test_subdirectory_and_git_display_preferences_do_not_hide_additions(self):
        self.terms('private-marker\n')
        (self.repo / 'base.txt').write_text('safe\n')
        self.commit()
        base = self.git('rev-parse', 'HEAD')
        nested = self.repo / 'nested'
        nested.mkdir()
        (nested / 'file.txt').write_text('PRIVATE-MARKER\n')
        (self.repo / 'outside.txt').write_text('PRIVATE-MARKER\n')
        self.commit()
        self.git('config', 'color.ui', 'always')
        self.git('config', 'diff.outputIndicatorNew', '>')
        for args in ((base + '..HEAD',), ('--all',)):
            result = self.check(*args, cwd=nested)
            self.assertEqual(result.returncode, 1, result.stderr)
            for path in ('nested/file.txt', 'outside.txt'):
                self.assertIn(path + ':1 私人词第 1 条', result.stdout)

    def hook(self, rows):
        return subprocess.run([str(ROOT / '.githooks/pre-push'), 'origin', 'unused'],
                              input=rows, cwd=self.repo, env=self.env, capture_output=True, text=True)

    def test_hook_checks_new_branch_update_force_push_and_skips_deletion(self):
        self.terms()
        (self.repo / 'file.txt').write_text('safe\n')
        self.commit()
        base = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', base)
        secret = 'sk' + '-' + 'a' * 20
        (self.repo / 'file.txt').write_text(secret + '\n')
        self.commit()
        tip = self.git('rev-parse', 'HEAD')
        zero = '0' * 40
        for remote in (zero, base):
            result = self.hook(f'refs/heads/work {tip} refs/heads/work {remote}\n')
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertEqual(self.hook(f'(delete) {zero} refs/heads/work {tip}\n').returncode, 0)
        self.git('checkout', '-q', '--detach', base)
        (self.repo / 'clean.txt').write_text('safe\n')
        self.commit()
        clean_tip = self.git('rev-parse', 'HEAD')
        self.assertEqual(self.hook(f'refs/heads/work {clean_tip} refs/heads/work {tip}\n').returncode, 0)
        (self.config / 'private-terms').unlink()
        self.assertNotEqual(self.hook(f'refs/heads/work {clean_tip} refs/heads/work {base}\n').returncode, 0)


class ShapesTests(unittest.TestCase):
    def test_kimi_seed_is_portable_and_declares_a_runtime_guard_placeholder(self):
        seed = ROOT / 'kimi-review-home/config.toml'
        self.assertNotIn('/root', seed.read_text())
        config = tomllib.loads(seed.read_text())
        self.assertEqual(config['hooks'][0]['command'], '__KIMI_GUARD_COMMAND__')
        self.assertEqual(sorted(str(p.relative_to(seed.parent)) for p in seed.parent.rglob('*') if p.is_file()),
                         ['config.toml', 'hooks/guard.mjs'])

    def test_shapes_agree_between_grep_python_and_redaction_with_left_boundary(self):
        import importlib.machinery
        import importlib.util
        loader = importlib.machinery.SourceFileLoader('privacy_review', str(ROOT / 'bin/review-pr'))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        review = importlib.util.module_from_spec(spec)
        loader.exec_module(review)
        sys.path.insert(0, str(ROOT / 'bin'))
        from _secret_shapes import load_shapes
        samples = ['sk' + '-' + 'a' * 16, 'ghp' + '_' + 'a' * 20,
                   'github' + '_pat_' + 'a', 'AI' + 'za' + 'a' * 20,
                   'AK' + 'IA' + 'A' * 16, 'xox' + 'b-' + 'a' * 10,
                   '-----' + 'BEGIN PRIVATE KEY' + '-----', 'tp' + '-' + 'a' * 48]
        for sample in samples:
            for before, expected in (('', True), (' ', True), (':', True), ('a', False), ('_', False), ('-', False)):
                text = before + sample
                with self.subTest(prefix=before, shape=samples.index(sample)):
                    grep = subprocess.run(['grep', '-Eq', '-f', str(ROOT / 'bin/_secret-shapes')],
                                          input=text, text=True, env=dict(os.environ, LC_ALL='C'))
                    self.assertEqual(grep.returncode == 0, expected)
                    self.assertEqual(any(p.search(text) for _, p in load_shapes()), expected)
                    self.assertEqual(review.redact(text), before + '[redacted]' if expected else text)
        harmless = 'codex/task-model-roles-closeout'
        self.assertEqual(review.redact(harmless), harmless)

    def test_shape_definitions_exist_only_in_the_shared_file(self):
        # Derive provider prefixes from the data, then find regex definitions,
        # including raw/triple-quoted strings, throughout the executable source.
        source = ROOT / 'bin/_secret-shapes'
        self.assertTrue(source.is_file())
        prefixes = [line.split(')', 1)[1].split('[', 1)[0]
                    for line in source.read_text().splitlines()]
        hits = []
        for path in (ROOT / 'bin').rglob('*'):
            if not path.is_file() or path == source or '__pycache__' in path.parts:
                continue
            for n, line in enumerate(path.read_text().splitlines(), 1):
                if any(prefix + '[' in line for prefix in prefixes):
                    hits.append(f'{path.relative_to(ROOT)}:{n}')
        self.assertEqual(hits, [])


if __name__ == '__main__':
    unittest.main()
