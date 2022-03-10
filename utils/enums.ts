export enum Status {
  None, // The submission doesn't have a pending status.
  Vouching, // The submission is in the state where it can be vouched for and crowdfunded.
  PendingRegistration, // The submission is in the state where it can be challenged. Or accepted to the list, if there are no challenges within the time limit.
  PendingRemoval, // The submission is in the state where it can be challenged. Or removed from the list, if there are no challenges within the time limit.
}

export enum Party {
  None, // Party per default when there is no challenger or requester. Also used for unconclusive ruling.
  Requester, // Party that made the request to change a status.
  Challenger, // Party that challenged the request to change a status.
}

export enum Reason {
  None, // No reason specified. This option should be used to challenge removal requests.
  IncorrectSubmission, // The submission does not comply with the submission rules.
  Deceased, // The submitter has existed but does not exist anymore.
  Duplicate, // The submitter is already registered. The challenger has to point to the identity already registered or to a duplicate submission.
  DoesNotExist, // The submitter is not real. For example, this can be used for videos showing computer generated persons.
}
