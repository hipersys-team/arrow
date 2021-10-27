
var citation = 0;

function showCitation() {
    if (citation == 0) {
      document.getElementById('citation').style='display:inline-block';
    } 
    else {
      document.getElementById('citation').style='display:none';
    }
    citation = 1 - citation;
  }