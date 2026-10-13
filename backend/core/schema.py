"""OpenAPI schema customization (Stage 4.17 §33 docs surface).

``drf_spectacular`` derives ``operationId`` from the URL path with path
variables stripped out. This project deliberately mounts the same URLconf at
both ``/api/`` and ``/api/v1/`` and exposes nested aliases such as
``/api/patients/{patient_uid}/medical-records/{uid}/history/`` next to the flat
``/api/medical-records/{uid}/history/``. With variables removed those distinct
operations collapse to the same id, so spectacular falls back to opaque numeral
suffixes and emits ``operationId ... has collisions`` warnings.

This schema keeps the variable names in the tokenized path, which yields a
unique (and still readable) id per operation while leaving tag derivation —
which uses the default, variable-stripped tokenization — untouched.
"""

import re

from drf_spectacular.openapi import AutoSchema
from drf_spectacular.settings import spectacular_settings


class UniqueOperationIdSchema(AutoSchema):
    """AutoSchema whose operation ids stay unique across mounted aliases."""

    def get_operation_id(self) -> str:
        tokenized_path = [
            token.replace("-", "_") for token in self._tokenize_path_with_vars()
        ]

        if self.method == "GET" and self._is_list_view():
            action = "list"
        else:
            action = self.method_mapping[self.method.lower()]

        if not tokenized_path:
            tokenized_path.append("root")

        if re.search(r"<drf_format_suffix\w*:\w+>", self.path_regex):
            tokenized_path.append("formatted")

        if spectacular_settings.OPERATION_ID_METHOD_POSITION == "PRE":
            return "_".join([action] + tokenized_path)
        return "_".join(tokenized_path + [action])

    def _tokenize_path_with_vars(self) -> list[str]:
        path = re.sub(
            pattern=self.path_prefix,
            repl="",
            string=self.path,
            flags=re.IGNORECASE,
        )
        parts = [part for part in path.strip("/").split("/") if part]
        # Keep variable *names* (drop the braces) so nested/flat/versioned
        # aliases of the same action resolve to different operation ids.
        return [part.strip("{}") for part in parts]
