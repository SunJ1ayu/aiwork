"""Read the ERE data also consumed by grep -E -f."""
from pathlib import Path
import re


def load_shapes():
    return [(line.split(')', 1)[1].split('[', 1)[0].rstrip(), re.compile(line))
            for line in Path(__file__).with_name('_secret-shapes').read_text().splitlines()]


def redact_shapes(text):
    spans = []
    for _, pattern in load_shapes():
        for match in pattern.finditer(text):
            start = match.start() + len(match.group(1))
            end = match.end()
            if text[start:end].startswith('-----'):
                # The shared shape identifies the opening delimiter; preserve
                # the old redact behavior of hiding the entire PEM payload.
                closing = text.find('-----END ', end)
                finish = text.find('-----', closing + len('-----END ')) if closing >= 0 else -1
                end = finish + 5 if finish >= 0 else len(text)
            spans.append((start, end))
    merged = []
    for start, end in sorted(set(spans)):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    for start, end in reversed(merged):
        text = text[:start] + '[redacted]' + text[end:]
    return text
