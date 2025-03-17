using CloudSoft.Models;
using CloudSoft.Repositories;

namespace CloudSoft.Services;

public class NewsletterService : INewsletterService
{

    private readonly ISubscriberRepository _subscriberRepository;
    
    public NewsletterService(ISubscriberRepository subscriberRepository)
    {
        _subscriberRepository = subscriberRepository;
    }
    
    public async Task<OperationResult> SignUpForNewsletterAsync(Subscriber subscriber)
    {
        // Check subscriber if not null and has a valid email
        if (subscriber == null || string.IsNullOrWhiteSpace(subscriber.Email))
        {
            return OperationResult.Failure("Invalid subscriber information");
        }
        
        // Check if the email is already registered
        if (await _subscriberRepository.GetByEmailAsync(subscriber.Email) != null)
        {
            return OperationResult.Failure("Email is already subscribed");
        }
        
        // Add the subscriber to the repostiry
        var success = await _subscriberRepository.AddAsync(subscriber);

        if (!success)
        {
            return OperationResult.Failure("Failed to add subscriber");
        }
        
        // Return success
        return OperationResult.Success($"Welcome to the newsletter {subscriber.Name}!");
        
    }

    public async Task<OperationResult> OptOutFromNewsletterAsync(string email)
    {
        // Check if email is valid

        if (string.IsNullOrEmpty(email))
        {
            return OperationResult.Failure("Invalid email");
        }

        // Find the subscriber by email
        var subscriber = await _subscriberRepository.GetByEmailAsync(email);

        if (subscriber == null)
        {
            return OperationResult.Failure("Email not found in the list");
        }

        // Remove the subscriber from the list
        var success = await _subscriberRepository.DeleteAsync(email);

        if (!success)
        {
            return OperationResult.Failure("Failed to remove subscriber");
        }

        // Return a success message
        return OperationResult.Success($"Successfully unsubscribed from the newsletter");
    }
    
    public async Task<IEnumerable<Subscriber>> GetActiveSubscriberAsync()
    {
        // Get all subscribers from the repository and convert to the list to match the interface
        var subscribers = await _subscriberRepository.GetAllAsync();
        return subscribers.ToList();
    }

}
