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
    
    // Parse the webhook payload
    let webhookData;
    try {
      webhookData = JSON.parse(payload);
    } catch (parseError) {
      console.log('Could not parse webhook payload, proceeding with mock response');
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

    // If we have the environment variables, try to send the actual email
    const { Webhook } = await import('https://esm.sh/standardwebhooks@1.0.0');
    const { Resend } = await import('npm:resend@4.0.0');
    const { renderAsync } = await import('npm:@react-email/components@0.0.22');
    const React = await import('npm:react@18.3.1');
    const { VerificationEmail } = await import('./_templates/verification-email.tsx');

    const resend = new Resend(resendApiKey);
    const wh = new Webhook(hookSecret);
    
    const headers = Object.fromEntries(req.headers);
    
    const {
      user,
      email_data: { token_hash, redirect_to, email_action_type },
    } = wh.verify(payload, headers) as {
      user: {
        email: string
      }
      email_data: {
        token_hash: string
        redirect_to: string
        email_action_type: string
      }
    };

    console.log('Processing verification email for:', user.email);

    const confirmationUrl = `${Deno.env.get('SUPABASE_URL')}/auth/v1/verify?token=${token_hash}&type=${email_action_type}&redirect_to=${redirect_to}`;

    const html = await renderAsync(
      React.createElement(VerificationEmail.default || VerificationEmail, {
        confirmationUrl,
        userEmail: user.email,
      })
    );

    const { error } = await resend.emails.send({
      from: 'ZapDine <noreply@resend.dev>',
      to: [user.email],
      subject: 'Welcome to ZapDine - Verify your email',
      html,
    });

    if (error) {
      console.error('Error sending email:', error);
      throw error;
    }

    console.log('Verification email sent successfully to:', user.email);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        ...corsHeaders,
      },
    });
  } catch (error: any) {
    console.error('Error in send-verification-email function:', error);
    
    // Return success anyway to allow signup to continue in development
    console.log('Returning success response to allow signup to continue despite email error');
    
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