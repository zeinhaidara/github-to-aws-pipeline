const stages = document.querySelectorAll(".stage");
let activeStage = 0;

function highlightStage() {
  stages.forEach((stage, index) => stage.classList.toggle("active", index === activeStage));
  activeStage = (activeStage + 1) % stages.length;
}

highlightStage();
setInterval(highlightStage, 1400);
