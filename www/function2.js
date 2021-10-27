
var citation2 = 0;

function showCitation2() {
    if (citation2 == 0) {
      document.getElementById('citation2').style='display:inline-block';
    } 
    else {
      document.getElementById('citation2').style='display:none';
    }
    citation2 = 1 - citation2;
  }