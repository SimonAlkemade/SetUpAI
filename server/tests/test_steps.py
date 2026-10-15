import pytest

from backends import steps_for


@pytest.mark.parametrize("strength", [0.05, 0.25, 0.3, 0.33, 0.5, 0.6, 0.75, 1.0])
def test_exactly_one_denoising_step(strength):
    # diffusers img2img denoises int(steps * strength) steps.
    assert int(steps_for(strength) * strength) == 1
