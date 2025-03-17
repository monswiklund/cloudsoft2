using CloudSoft.Configurations;
using CloudSoft.Models;
using CloudSoft.Services;
using CloudSoft.Repositories;
using Microsoft.Extensions.Options;
using CloudSoft.Storage;
using MongoDB.Driver;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllersWithViews();

// Check if MongoDB should be used (default to false if not set)
bool useMongoDb = builder.Configuration.GetValue<bool>("FeatureFlags:UseMongoDb");

if (useMongoDb)
{
    // Configure MongoDB
    builder.Services.Configure<MongoDbOptions>(
        builder.Configuration.GetSection(MongoDbOptions.SectionName));
    
    // Configure MongoDB Client
    builder.Services.AddSingleton<IMongoClient>(serviceProvider =>
    {
        var options = serviceProvider.GetRequiredService<IOptions<MongoDbOptions>>();
        return new MongoClient(options.Value.ConnectionString);
    });
    
    // Configure MongoDB collection
    builder.Services.AddSingleton<IMongoCollection<Subscriber>>(serviceProvider => {
        var options = serviceProvider.GetRequiredService<IOptions<MongoDbOptions>>();
        var mongoClient = serviceProvider.GetRequiredService<IMongoClient>();
        var database = mongoClient.GetDatabase(options.Value.DatabaseName);
        return database.GetCollection<Subscriber>(options.Value.SubscribersCollectionName);
    });
    
    // Register MongoDB Repository
    builder.Services.AddSingleton<ISubscriberRepository, MongoDbSubscriberRepository>();

    Console.WriteLine("Using MongoDB Repository");
}
else
{
    // Register InMemory Repository as fallback
    builder.Services.AddSingleton<ISubscriberRepository, InMemorySubscriberRepository>();

    Console.WriteLine("Using InMemory Repository");
}

// Register service (depends on Repositories)
builder.Services.AddScoped<INewsletterService, NewsletterService>();
var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();