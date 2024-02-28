import logging, sys
from robot.libraries.BuiltIn import BuiltIn
from robot import result, running
from robot.api.interfaces import ListenerV3

logger = logging.getLogger(__name__)


class Masker(ListenerV3):
    """Masking class for applying masks to robot output files
    """
    def __init__(self):
        self.mask = "*" * 32
        self.values_to_mask = None

    def end_suite(self, data: running.TestCase, result: result.TestCase):
        self.values_to_mask = BuiltIn().get_variable_value('${RW__MASKED}', default=[]) # robot api calls must be within the listener hook
        result.message = self._mask_values(result.message)

    def end_test(self, data: running.TestCase, result: result.TestCase):
        self.values_to_mask = BuiltIn().get_variable_value('${RW__MASKED}', default=[]) # robot api calls must be within the listener hook
        result.message = self._mask_values(result.message)
    
    def start_keyword(self, data: running.TestCase, result: result.TestCase):
        pass

    def end_keyword(self, data: running.TestCase, result: result.TestCase):
        self.values_to_mask = BuiltIn().get_variable_value('${RW__MASKED}', default=[]) # robot api calls must be within the listener hook
        result.message = self._mask_values(result.message)

    def log_message(self, message: result.Message):
        self.values_to_mask = BuiltIn().get_variable_value('${RW__MASKED}', default=[]) # robot api calls must be within the listener hook
        message.message = self._mask_values(message.message)

    def _mask_values(self, text):
        for mask_value in self.values_to_mask:
            text = text.replace(mask_value, self.mask)
        return text
