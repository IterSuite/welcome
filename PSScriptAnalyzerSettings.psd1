# PSScriptAnalyzerSettings.psd1 — the rules we hold the bootstrap scripts to, and
# the two we deliberately don't. PSScriptAnalyzer reads this via `-Settings` (see
# .github/workflows/verify.yml). Excluding a rule here is a decision ON THE RECORD,
# not a silencing: each one below has a reason it does not apply to a script whose
# whole job is to talk to a human and be delivered through `iwr | iex`.
@{
    ExcludeRules = @(
        # PSAvoidUsingWriteHost — Write-Host is CORRECT here. This is an interactive
        # installer: its entire purpose is to print colored, ordered progress to a
        # person at a terminal (the Ok/Bad/Warn/Step helpers). Write-Output would
        # pollute the pipeline and drop the color; Write-Information is off by default,
        # so the user would see nothing. The rule guards libraries; this is a UI.
        'PSAvoidUsingWriteHost',

        # PSUseBOMForUnicodeEncodedFile — this script is delivered by
        # `iwr -useb … | iex`, streamed as a string and executed, never saved and run
        # as a file. A UTF-8 BOM is inert at best on that path and at worst a leading
        # U+FEFF that `iex` can choke on. The non-ASCII here is decorative (the ✓ ✗ ▸ —
        # in the output). We keep the file BOM-less on purpose, so the one delivery
        # path that actually matters cannot break.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
