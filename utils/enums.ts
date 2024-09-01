export enum Status {
  Vouching, // Request requires vouches / funding to advance to the next state. Should not be in this state for revocation requests.
  Resolving, // Request is resolving and can be challenged within the time limit.
  Disputed, // Request has been challenged.
  Resolved // Request has been resolved.
}

export enum Party {
  None, // Party per default when there is no challenger or requester. Also used for unconclusive ruling.
  Requester, // Party that made the request to change a status.
  Challenger, // Party that challenged the request to change a status.
}

export enum Reason {
  None, // No reason specified. This option should be used to challenge removal requests.
  IncorrectSubmission, // Request does not comply with the rules.
  IdentityTheft, // Attempt to claim the humanity ID of another human.
  SybilAttack, // Duplicate or human does not exist.
  Deceased // Human has existed but does not exist anymore.
}
