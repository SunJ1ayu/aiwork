"""Public runtime-setting contract shared by adapter and controller tests.

Rows are adapter, option, variable, direct fallback, reader fallback, file sample.
These are expected caller-visible values, independent of the implementation registry.
"""

RUNTIME_CASES = (
    ('subcodex', 'timeout', 'SUBCODEX_TIMEOUT', '1500', '2400', '6101'),
    ('subcursor', 'timeout', 'CURSOR_TIMEOUT', '900', '2400', '6102'),
    ('subdeepseek-agent', 'timeout', 'DEEPSEEK_TIMEOUT', '900', '2400', '6103'),
    ('subkimi', 'timeout', 'KIMI_TIMEOUT', '1500', '2400', '6104'),
    ('submimo', 'timeout', 'MIMO_TIMEOUT', '5400', '5400', '6105'),
    ('subdeepseek-agent', 'max_turns', 'DEEPSEEK_MAX_TURNS', '200', '200', '311'),
    ('submimo', 'max_turns', 'MIMO_MAX_TURNS', '200', '200', '312'),
    ('subcodex', 'effort', 'SUBCODEX_EFFORT', 'high', 'high', 'medium'),
)
