contract Raffle {
  uint private chosenNumber;
  address private winnerParticipant;
  uint8 maxParticipants;
  uint8 minParticipants;
  uint8 joinedParticipants;
  address organizer;
  bool raffleFinished = false;
  address[] participants;
  mapping (address => bool) participantsMapping;
  event ChooseWinner(uint _chosenNumber,address winner);
  event RandomNumberGenerated(uint);
  function Raffle(){
    address _org = msg.sender; 
    uint8 _min = 2; 
    uint8 _max = 10; 
    require(_min < _max && _min >=2 && _max <=50);
    organizer = _org;
    chosenNumber = 999;
    maxParticipants = _max;
    minParticipants = _min;
  }
function() payable {}
function joinraffle(){
    require(!raffleFinished);
    require(msg.sender != organizer);
    require(joinedParticipants + 1 < maxParticipants);
    require(!participantsMapping[msg.sender]);
    participants.push(msg.sender);
    participantsMapping[msg.sender] = true;
    joinedParticipants ++;
  }
function chooseWinner(uint _chosenNum) internal{
    chosenNumber = _chosenNum;
    winnerParticipant = participants[chosenNumber];
    ChooseWinner(chosenNumber,participants[chosenNumber]);
}
function generateRandomNum(){
    require(!raffleFinished);
    require(joinedParticipants >=minParticipants && joinedParticipants<=maxParticipants);
    raffleFinished=true;
    
    chooseWinner(0); //We'll replace this with a call to Oraclize service later on.
}
function getChosenNumber() constant returns (uint) {
    return chosenNumber;
  }
function getWinnerAddress() constant returns (address) {
    return winnerParticipant;
  }
function getParticipants() constant returns (address[]) {
    return participants;
  }
}