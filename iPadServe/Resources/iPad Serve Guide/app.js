const dialog = document.querySelector("#introDialog");
const openIntro = document.querySelector("#openIntro");
const previewModal = document.querySelector("#previewModal");
const revealItems = document.querySelectorAll(".reveal");

function showIntro() {
  if (dialog && typeof dialog.showModal === "function") {
    dialog.showModal();
  }
}

openIntro?.addEventListener("click", showIntro);
previewModal?.addEventListener("click", showIntro);

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.2 });

revealItems.forEach((item) => observer.observe(item));
