# Independent goal-to-design challenge

User wants aiwork main arbiter to inspect explore/review candidate pools and choose task-appropriate models, including TWO DIFFERENT Cursor models in ONE run, instead of a fixed transport roster. Preserve archive/evidence/safety contracts. We have not selected a final design. Propose one minimal concrete direction, challenge whether fulfilling this request could still fail the user's goal, identify the riskiest assumptions and smallest experiments.

Read repository code (bin/_panel-roster-lib.sh, panel-review, panel-explore, _review_result.py, track-record, panel-roster, _panel_slice.py, subcursor and relevant tests). Existing CLI exposes one global CURSOR_MODEL and one subcursor roster entry; normal review forbids --pin-leg outside scoped reviews; health keyed by leg; explore hardcodes dispatch. Real Cursor CLI lists multiple explicit models. Coverage counts different model families in one run with same subject and actual identity validation. Archived evidence must remain readable.

Do not read any tracks/model-selection files or any *my-review* files: these are the main arbiter's independent direction, excluded from your task. No edits, no tests, no agents. Distinguish facts you verified from hypotheses. Do not infer independence from corporate names, and do not claim quota remaining from merely listing a model.
