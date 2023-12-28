document.addEventListener('DOMContentLoaded', function() {
    var form = document.querySelector('form');
    var submitBtn = document.getElementById('submitBtn');
    var originalButtonText = submitBtn.innerHTML;

    form.addEventListener('submit', function(event) {
        // Optionally, prevent the default form submission if using AJAX
        // event.preventDefault();

        // Replace the button text with the spinner
        submitBtn.innerHTML = '<div class="spinner"></div>';

        // Mock processing time with setTimeout (replace with your form submission logic)
        setTimeout(function() {
            submitBtn.innerHTML = originalButtonText;
        }, 3000); // Adjust this timeout as per your actual form submission logic
    });
});
