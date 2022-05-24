// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

enum Reason {
    None, // No reason specified. This option should be used to challenge removal requests.
    IncorrectSubmission, // The submission does not comply with the submission rules.
    Deceased, // The submitter has existed but does not exist anymore.
    Duplicate, // The submitter is already registered. The challenger has to point to the identity already registered or to a duplicate submission.
    DoesNotExist // The submitter is not real. For example, this can be used for videos showing computer generated persons.
}
