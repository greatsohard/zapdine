import { serve } from "https://deno.land/std@0.190.0/http/server.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const handler = async (req: Request): Promise<Response> => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const payload = await req.text()
    console.log('Received webhook payload for verification email');
    
    // Parse the webhook payload
    let webhookData;
    try {
      webhookData = JSON.parse(payload);
      console.log('Webhook data parsed successfully');
    } catch (parseError) {
      console.log('Could not parse webhook payload:', parseError);
      // Return success to allow signup to continue
      return new Response(JSON.stringify({ 
        success: true, 
        message: 'Signup completed - email verification skipped due to payload parsing issue' 
      }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          ...corsHeaders,
        },
      });
    }

    // Check if we have the required environment variables
    const resendApiKey = Deno.env.get('RESEND_API_KEY');
    const hookSecret = Deno.env.get('SEND_EMAIL_HOOK_SECRET');

    if (!resendApiKey || !hookSecret) {
      console.log('Email service not configured - RESEND_API_KEY or SEND_EMAIL_HOOK_SECRET missing');
      console.log('Returning success response to allow signup to continue');
      
      return new Response(JSON.stringify({ 
        success: true, 
        message: 'Email service not configured - signup allowed without email verification' 
      }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          ...corsHeaders,
        },
      });
    }

    // Try to send the actual email with proper error handling
    try {
      console.log('Attempting to import dependencies...');
      
      // Import dependencies with error handling
      const { Webhook } = await import('https://esm.sh/standardwebhooks@1.0.0');
      const { Resend } = await import('https://esm.sh/resend@4.0.0');
      
      console.log('Dependencies imported successfully');

      const resend = new Resend(resendApiKey);
      const wh = new Webhook(hookSecret);
      
      const headers = Object.fromEntries(req.headers);
      
      let verifiedData;
      try {
        verifiedData = wh.verify(payload, headers) as {
          user: {
            email: string
          }
          email_data: {
            token_hash: string
            redirect_to: string
            email_action_type: string
          }
        };
      } catch (verifyError) {
        console.error('Webhook verification failed:', verifyError);
        // Return success to allow signup to continue
        return new Response(JSON.stringify({ 
          success: true, 
          message: 'Signup completed - email verification skipped due to webhook verification issue' 
        }), {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            ...corsHeaders,
          },
        });
      }

      const { user, email_data: { token_hash, redirect_to, email_action_type } } = verifiedData;

      console.log('Processing verification email for:', user.email);

      const confirmationUrl = `${Deno.env.get('SUPABASE_URL')}/auth/v1/verify?token=${token_hash}&type=${email_action_type}&redirect_to=${redirect_to}`;

      // Create a simple HTML email template instead of using React Email
      const html = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Welcome to ZapDine</title>
          <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #f59e0b, #d97706); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
            .content { background: #fff; padding: 30px; border: 1px solid #e5e7eb; border-top: none; }
            .button { display: inline-block; background: #f59e0b; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: bold; margin: 20px 0; }
            .footer { background: #f9fafb; padding: 20px; text-align: center; border-radius: 0 0 8px 8px; color: #6b7280; font-size: 14px; }
            .logo { font-size: 24px; font-weight: bold; margin-bottom: 10px; }
          </style>
        </head>
        <body>
          <div class="header">
            <div class="logo">🍽️ ZapDine</div>
            <h1>Welcome to ZapDine!</h1>
            <p>Your restaurant management journey starts here</p>
          </div>
          <div class="content">
            <h2>Hi there! 👋</h2>
            <p>Thank you for joining ZapDine! We're excited to help you streamline your restaurant operations and create amazing dining experiences.</p>
            
            <p>To get started, please verify your email address by clicking the button below:</p>
            
            <div style="text-align: center;">
              <a href="${confirmationUrl}" class="button">Verify Email Address</a>
            </div>
            
            <p>Once verified, you'll have access to:</p>
            <ul>
              <li>✨ Complete restaurant management dashboard</li>
              <li>📱 QR code menu system</li>
              <li>📊 Real-time order tracking</li>
              <li>💰 Sales analytics and reporting</li>
              <li>👥 Staff management tools</li>
              <li>🎯 And much more!</li>
            </ul>
            
            <p><strong>Your 14-day free trial starts now!</strong> No credit card required.</p>
            
            <p>If you didn't create this account, you can safely ignore this email.</p>
            
            <p>Welcome aboard!</p>
            <p>The ZapDine Team</p>
          </div>
          <div class="footer">
            <p>This email was sent to ${user.email}</p>
            <p>Powered by <a href="https://spslabs.vercel.app" style="color: #f59e0b;">SPS Labs</a></p>
          </div>
        </body>
        </html>
      `;

      const { error } = await resend.emails.send({
        from: 'ZapDine <noreply@resend.dev>',
        to: [user.email],
        subject: '🎉 Welcome to ZapDine - Verify your email',
        html,
      });

      if (error) {
        console.error('Error sending email:', error);
        // Return success anyway to allow signup to continue
        return new Response(JSON.stringify({ 
          success: true, 
          message: 'Signup completed - email verification skipped due to email sending issue' 
        }), {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            ...corsHeaders,
          },
        });
      }

      console.log('Verification email sent successfully to:', user.email);

      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          ...corsHeaders,
        },
      });

    } catch (importError) {
      console.error('Error importing dependencies or sending email:', importError);
      
      // Return success anyway to allow signup to continue
      console.log('Returning success response to allow signup to continue despite email error');
      
      return new Response(JSON.stringify({ 
        success: true, 
        message: 'Signup completed - email verification skipped due to dependency issue' 
      }), {
        status: 200,
        headers: { 
          'Content-Type': 'application/json', 
          ...corsHeaders 
        },
      });
    }

  } catch (error: any) {
    console.error('Error in send-verification-email function:', error);
    
    // Always return success to allow signup to continue in development
    console.log('Returning success response to allow signup to continue despite error');
    
    return new Response(JSON.stringify({ 
      success: true, 
      message: 'Signup completed - email verification skipped due to configuration issue' 
    }), {
      status: 200,
      headers: { 
        'Content-Type': 'application/json', 
        ...corsHeaders 
      },
    });
  }
}

serve(handler);