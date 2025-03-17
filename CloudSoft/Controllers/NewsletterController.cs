using CloudSoft.Models;
using CloudSoft.Services;
using Microsoft.AspNetCore.Mvc;

namespace CloudSoft.Controllers;

public class NewsletterController : Controller
{
    // Create a "database" of subscribers for demonstration purposes

    private readonly INewsletterService _newsletterService;

    public NewsletterController(INewsletterService newsletterService)
    {
        // Inject the INewsletterService via the contstructor from Dependency Injection
        _newsletterService = newsletterService;
    }


    [HttpGet]
    public IActionResult Subscribe()
    {
        return View();
    }


    [HttpPost]
    public async Task<IActionResult> Subscribe(Subscriber subscriber)
    {
        // Validate the model
        if (!ModelState.IsValid)
        {
            return View(subscriber);
        }

        // Check if the email is aldready subscribed and return a general model level error
        var result = await _newsletterService.SignUpForNewsletterAsync(subscriber);
        if (!result.IsSuccess)
        {
            ModelState.AddModelError("Email", result.Message);
            return View(subscriber);
        }

        // Write to the console
        Console.WriteLine($"New subscription - Name: {subscriber.Name} Email: {subscriber.Email}");

        // Send a message to the user
        TempData["SuccessMessage"] = $"Thank you for subscribing, {subscriber.Name}! You will receive our newsletter at {subscriber.Email}";

        // Return the view (using the POST-REDIRECT-GET pattern)
        return RedirectToAction(nameof(Subscribe));  // use nameof() to find the action by name during compile time
    }

    [HttpGet]
    public async Task<IActionResult> Subscribers()
    {
        var subscribers = (await _newsletterService.GetActiveSubscriberAsync()).ToList();
        return View(subscribers);
    }

    [HttpGet]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Unsubscribe(string email)
    {
        var result = await _newsletterService.OptOutFromNewsletterAsync(email);
        if (result.IsSuccess)
        {
            TempData["SuccessMessage"] = result.Message;

        }
        return RedirectToAction(nameof(Subscribe));
    }
}